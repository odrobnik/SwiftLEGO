import SwiftUI
import QuickLook

@MainActor
@Observable
final class QuickLookPresenter {
    var previewURL: URL?

    /// Items whose preview is being downloaded. Observed, so thumbnails show a spinner.
    private var loadingIDs: Set<AnyHashable> = []

    func present<Item: QuickLookPreviewable>(_ item: Item) {
        guard (item.quickLookPreferredURL ?? item.quickLookFallbackURL) != nil else {
            return
        }

        let id = item.quickLookID
        guard loadingIDs.insert(id).inserted else { return }

        Task {
            let preview = await AssetQuickLookStore.shared.previewURL(
                for: item,
                preferredURL: item.quickLookPreferredURL,
                fallbackURL: item.quickLookFallbackURL
            )

            if let preview {
                previewURL = preview
            }
            loadingIDs.remove(id)
        }
    }

    func isLoading<Item: QuickLookPreviewable>(_ item: Item) -> Bool {
        loadingIDs.contains(item.quickLookID)
    }
}

private struct QuickLookPresenterKey: EnvironmentKey {
    static let defaultValue: QuickLookPresenter? = nil
}

extension EnvironmentValues {
    var quickLookPresenter: QuickLookPresenter? {
        get { self[QuickLookPresenterKey.self] }
        set { self[QuickLookPresenterKey.self] = newValue }
    }
}

private struct QuickLookPresenterModifier: ViewModifier {
    @State private var presenter = QuickLookPresenter()

    func body(content: Content) -> some View {
        content
            .environment(\.quickLookPresenter, presenter)
            .quickLookPreview($presenter.previewURL)
    }
}

extension View {
    /// Lets `QuickLookThumbnail` and `QuickLookMenuButton` inside this view present previews.
    func quickLookPresenter() -> some View {
        modifier(QuickLookPresenterModifier())
    }
}
