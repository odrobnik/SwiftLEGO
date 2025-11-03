import Foundation
import CryptoKit
import BrickCore

actor PartQuickLookStore {
    static let shared = PartQuickLookStore()

    private var cachedPreviews: [URL: URL] = [:]

    func previewURL(preferredURL: URL, fallbackURL: URL?) async -> URL? {
        if let cached = cachedPreviews[preferredURL] {
            return cached
        }

        if let fallbackURL,
           let cachedFallback = cachedPreviews[fallbackURL] {
            cachedPreviews[preferredURL] = cachedFallback
            return cachedFallback
        }

        if let preview = try? await fetchPreview(for: preferredURL) {
            cachedPreviews[preferredURL] = preview
            return preview
        }

        guard let fallbackURL else { return nil }

        if let cachedFallback = cachedPreviews[fallbackURL] {
            cachedPreviews[preferredURL] = cachedFallback
            return cachedFallback
        }

        if let fallbackPreview = try? await fetchPreview(for: fallbackURL) {
            cachedPreviews[fallbackURL] = fallbackPreview
            cachedPreviews[preferredURL] = fallbackPreview
            return fallbackPreview
        }

        return nil
    }

    private func fetchPreview(for url: URL) async throws -> URL {
        let data = try await ThumbnailCacheManager.shared.data(for: url)
        let destination = previewFileURL(for: url)
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return destination
    }

    private func previewFileURL(for url: URL) -> URL {
        let hash = sha256(url.absoluteString)
        var destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("part-preview-\(hash)", isDirectory: false)
        let pathExtension = url.pathExtension
        if !pathExtension.isEmpty {
            destination = destination.appendingPathExtension(pathExtension)
        }
        return destination
    }

    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
