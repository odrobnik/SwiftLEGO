import SwiftUI
import UIKit
import BrickCore

enum ThumbnailImagePhase {
    case empty
    case loading
    case success(Image)
    case failure(ThumbnailImageErrorState)
}

struct ThumbnailImageErrorState {
    let error: Error
    /// Loads the image again, or `nil` when the server said there is no image and
    /// asking again cannot change that.
    let retry: (() -> Void)?
}

private enum ThumbnailImageError: LocalizedError {
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .decodingFailed:
            return "The image data is invalid."
        }
    }
}

/// Loads a thumbnail through `ThumbnailCacheManager` while the view is on screen and
/// hands each loading phase to `content`.
struct ThumbnailImage<Content: View>: View {
    let url: URL?
    var cache: ThumbnailCacheManager = .shared
    /// Asked when the server has no image at `url`, for where the image lives now;
    /// that URL is then loaded in its place.
    var replacementURL: (@MainActor () async -> URL?)? = nil
    @ViewBuilder let content: (ThumbnailImagePhase) -> Content

    @State private var phase: ThumbnailImagePhase = .empty
    /// The URL `phase` shows the image of, so reappearing doesn't load it again.
    @State private var loadedURL: URL?
    /// Bumped by Retry to restart the load for the same URL.
    @State private var attempt = 0

    var body: some View {
        content(phase)
            .task(id: LoadRequest(url: url, attempt: attempt)) {
                await load()
            }
    }

    private struct LoadRequest: Equatable {
        let url: URL?
        let attempt: Int
    }

    private func load() async {
        guard let url else {
            phase = .empty
            loadedURL = nil
            return
        }

        if loadedURL == url, case .success = phase {
            return
        }

        phase = .loading
        loadedURL = nil

        do {
            let (image, imageURL) = try await loadImage(at: url)
            phase = .success(image)
            loadedURL = imageURL
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }

            let isNotFound = (error as? ThumbnailCacheError)?.isNotFound == true
            phase = .failure(ThumbnailImageErrorState(error: error, retry: isNotFound ? nil : {
                attempt += 1
            }))
        }
    }

    /// The image at `url` or, when the server has none there, at the URL
    /// `replacementURL` says it moved to.
    private func loadImage(at url: URL) async throws -> (Image, URL) {
        do {
            return (try await image(at: url), url)
        } catch let error as ThumbnailCacheError where error.isNotFound {
            guard let replacementURL,
                  let replacement = await replacementURL(),
                  replacement != url else {
                throw error
            }

            try Task.checkCancellation()
            return (try await image(at: replacement), replacement)
        }
    }

    private func image(at url: URL) async throws -> Image {
        let data = try await cache.data(for: url)
        try Task.checkCancellation()

        guard let image = UIImage(data: data) else {
            await cache.removeCachedData(for: url)
            throw ThumbnailImageError.decodingFailed
        }

        return Image(uiImage: image)
    }
}

extension ThumbnailImage where Content == DefaultThumbnailImageContent {
    init(url: URL?, cache: ThumbnailCacheManager = .shared) {
        self.init(url: url, cache: cache) { phase in
            DefaultThumbnailImageContent(phase: phase)
        }
    }
}

struct DefaultThumbnailImageContent: View {
    let phase: ThumbnailImagePhase

    var body: some View {
        switch phase {
        case .empty:
            Color.clear
        case .loading:
            ProgressView()
                .progressViewStyle(.circular)
        case .success(let image):
            image
                .resizable()
                .scaledToFit()
        case .failure(let state):
            if let retry = state.retry {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.red)
                    Button("Retry", action: retry)
                        .buttonStyle(.borderedProminent)
                }
                .padding(12)
            } else {
                Color.clear
            }
        }
    }
}
