import Foundation
import CryptoKit

public actor ThumbnailCacheManager {
    public static let shared = ThumbnailCacheManager()

    private let maxConcurrentDownloads: Int
    private let session: URLSession
    private let fileManager: FileManager
    private let cacheDirectory: URL

    private var memoryCache: [URL: Data] = [:]
    private var memoryCacheOrder: [URL] = []
    private let memoryCacheLimit = 100

    private var activeTasks: [URL: Task<Data, Error>] = [:]

    private var availablePermits: Int
    private var waitingContinuations: [CheckedContinuation<Void, Never>] = []

    public init(
        maxConcurrentDownloads: Int = 4,
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) {
        precondition(maxConcurrentDownloads > 0, "maxConcurrentDownloads must be at least 1")
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.session = session
        self.fileManager = fileManager
        self.availablePermits = maxConcurrentDownloads

        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let cacheDirectory = cachesDirectory.appendingPathComponent("ThumbnailCache", isDirectory: true)
        self.cacheDirectory = cacheDirectory

        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }

    public func data(for url: URL) async throws -> Data {
        if let cached = memoryCache[url] {
            updateMemoryOrder(for: url)
            return cached
        }

        let diskLocation = fileURL(for: url)
        if let diskData = try? Data(contentsOf: diskLocation) {
            storeInMemory(diskData, for: url)
            return diskData
        }
        if fileManager.fileExists(atPath: diskLocation.path) {
            try? fileManager.removeItem(at: diskLocation)
        }

        if let task = activeTasks[url] {
            return try await task.value
        }

        let task = Task<Data, Error> { [weak self] in
            guard let self else { throw ThumbnailCacheError.managerDeallocated }
            return try await self.fetchData(for: url)
        }

        activeTasks[url] = task

        do {
            let data = try await task.value
            activeTasks[url] = nil
            return data
        } catch {
            activeTasks[url] = nil
            throw error
        }
    }

    private func fetchData(for url: URL) async throws -> Data {
        await acquirePermit()
        defer { releasePermit() }

        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        let (data, response) = try await session.data(for: request)

        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ThumbnailCacheError.invalidResponse(statusCode: nil)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ThumbnailCacheError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        guard !data.isEmpty else {
            throw ThumbnailCacheError.emptyData
        }

        storeOnDisk(data, for: url)
        storeInMemory(data, for: url)

        return data
    }

    private func acquirePermit() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waitingContinuations.append(continuation)
        }
    }

    private func releasePermit() {
        if let continuation = waitingContinuations.first {
            waitingContinuations.removeFirst()
            continuation.resume()
        } else {
            availablePermits += 1
            if availablePermits > maxConcurrentDownloads {
                availablePermits = maxConcurrentDownloads
            }
        }
    }

    private func storeInMemory(_ data: Data, for url: URL) {
        memoryCache[url] = data
        updateMemoryOrder(for: url)
        trimMemoryCacheIfNeeded()
    }

    private func updateMemoryOrder(for url: URL) {
        memoryCacheOrder.removeAll { $0 == url }
        memoryCacheOrder.insert(url, at: 0)
    }

    private func trimMemoryCacheIfNeeded() {
        guard memoryCacheOrder.count > memoryCacheLimit else { return }

        let urlsToRemove = memoryCacheOrder.dropFirst(memoryCacheLimit)
        for url in urlsToRemove {
            memoryCache.removeValue(forKey: url)
        }
        memoryCacheOrder = Array(memoryCacheOrder.prefix(memoryCacheLimit))
    }

    private func storeOnDisk(_ data: Data, for url: URL) {
        let destination = fileURL(for: url)
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            // If we fail to write to disk, just ignore but remove any partial file.
            try? fileManager.removeItem(at: destination)
        }
    }

    public func removeCachedData(for url: URL) {
        memoryCache.removeValue(forKey: url)
        memoryCacheOrder.removeAll(where: { $0 == url })
        let destination = fileURL(for: url)
        try? fileManager.removeItem(at: destination)
    }

    private func fileURL(for url: URL) -> URL {
        let hash = sha256(url.absoluteString)
        return cacheDirectory.appendingPathComponent(hash, isDirectory: false)
    }

    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public enum ThumbnailCacheError: Error {
    case invalidResponse(statusCode: Int?)
    case emptyData
    case managerDeallocated
}
