import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ThumbnailImagePhase {
    case empty
    case loading
    case success(Image)
    case failure(ThumbnailImageErrorState)
}

struct ThumbnailImageErrorState {
    let error: Error
    let retry: () -> Void
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

struct ThumbnailImage<Content: View>: View {
    private let url: URL?
    @StateObject private var viewModel: ThumbnailImageViewModel
    private let content: (ThumbnailImagePhase) -> Content

    init(
        url: URL?,
        cache: ThumbnailCacheManager = .shared,
        @ViewBuilder content: @escaping (ThumbnailImagePhase) -> Content
    ) {
        self.url = url
        _viewModel = StateObject(wrappedValue: ThumbnailImageViewModel(url: url, cache: cache))
        self.content = content
    }

    init(
        url: URL?,
        cache: ThumbnailCacheManager = .shared
    ) where Content == DefaultThumbnailImageContent {
        self.init(url: url, cache: cache) { phase in
            DefaultThumbnailImageContent(phase: phase)
        }
    }

    var body: some View {
        content(viewModel.phase)
            .onAppear {
                viewModel.startLoadingIfNeeded()
            }
            .onChange(of: url) { _, newValue in
                viewModel.setURL(newValue)
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
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.red)
                Button("Retry") {
                    state.retry()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
    }
}

@MainActor
private final class ThumbnailImageViewModel: ObservableObject {
    @Published private(set) var phase: ThumbnailImagePhase = .empty

    private let cache: ThumbnailCacheManager
    private var currentURL: URL?
    private var currentTask: Task<Void, Never>?
    private var lastSuccessfulURL: URL?
    private var hasStartedLoading = false

    init(url: URL?, cache: ThumbnailCacheManager) {
        self.cache = cache
        self.currentURL = url
    }

    deinit {
        currentTask?.cancel()
    }

    func startLoadingIfNeeded() {
        guard !hasStartedLoading else { return }
        hasStartedLoading = true
        loadImage(force: false)
    }

    func setURL(_ url: URL?) {
        guard url != currentURL else { return }
        currentURL = url
        lastSuccessfulURL = nil
        hasStartedLoading = false
        loadImage(force: true)
    }

    func retry(force: Bool = true) {
        loadImage(force: force)
    }

    private func loadImage(force: Bool) {
        guard let url = currentURL else {
            phase = .empty
            lastSuccessfulURL = nil
            hasStartedLoading = false
            currentTask?.cancel()
            currentTask = nil
            return
        }

        if !force,
           let lastURL = lastSuccessfulURL,
           lastURL == url,
           case .success = phase {
            return
        }

        hasStartedLoading = true
        phase = .loading
        currentTask?.cancel()

        let cache = cache

        currentTask = Task { [weak self] in
            guard let self else { return }

            do {
                let data = try await cache.data(for: url)
                guard !Task.isCancelled else { return }

                guard let image = self.makeImage(from: data) else {
                    await cache.removeCachedData(for: url)
                    throw ThumbnailImageError.decodingFailed
                }

                await MainActor.run {
                    self.lastSuccessfulURL = url
                    self.phase = .success(image)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                let retryAction: () -> Void = { [weak self] in
                    Task { @MainActor in
                        self?.retry(force: true)
                    }
                }

                await MainActor.run {
                    self.phase = .failure(
                        ThumbnailImageErrorState(
                            error: error,
                            retry: retryAction
                        )
                    )
                }
            }
        }
    }

    private func makeImage(from data: Data) -> Image? {
        #if os(macOS)
            guard let nsImage = NSImage(data: data) else { return nil }
            return Image(nsImage: nsImage)
        #else
            guard let uiImage = UIImage(data: data) else { return nil }
            return Image(uiImage: uiImage)
        #endif
    }
}
