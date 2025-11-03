import Foundation
import BrickCore

actor AssetQuickLookStore {
    static let shared = AssetQuickLookStore()

    private var cachedPreviews: [URL: URL] = [:]

    func previewURL(for item: any QuickLookPreviewable, preferredURL: URL?, fallbackURL: URL?) async -> URL? {
        if let preferredURL,
           let cached = cachedPreviews[preferredURL] {
            return cached
        }

        if let fallbackURL,
           let preferredURL,
           let cachedFallback = cachedPreviews[fallbackURL] {
            cachedPreviews[preferredURL] = cachedFallback
            return cachedFallback
        }

        if let preferredURL,
           let preview = try? await fetchPreview(for: preferredURL, item: item) {
            cachedPreviews[preferredURL] = preview
            return preview
        }

        guard let fallbackURL else { return nil }

        if let cachedFallback = cachedPreviews[fallbackURL] {
            return cachedFallback
        }

        if let fallbackPreview = try? await fetchPreview(for: fallbackURL, item: item) {
            cachedPreviews[fallbackURL] = fallbackPreview
            return fallbackPreview
        }

        return nil
    }

    private func fetchPreview(for url: URL, item: any QuickLookPreviewable) async throws -> URL {
        let data = try await ThumbnailCacheManager.shared.data(for: url)
        let destination = previewFileURL(for: url, item: item)
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return destination
    }

    private func previewFileURL(for url: URL, item: any QuickLookPreviewable) -> URL {
        let sanitizedBase = sanitizeFilename(item.quickLookPreviewBaseName)
        let pathExtension = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        let filename = sanitizedBase.isEmpty ? "Preview" : sanitizedBase
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(filename, isDirectory: false)
            .appendingPathExtension(pathExtension)
    }

    private func sanitizeFilename(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|#%&!\n\r\t")
        let components = name.components(separatedBy: invalidCharacters)
        let sanitized = components.joined(separator: " ")
        let collapsed = sanitized
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed
    }
}
