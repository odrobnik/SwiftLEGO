import SwiftUI
import QuickLook

@MainActor
final class QuickLookPresenter: ObservableObject {
    @Published var previewURL: URL?

    private var loadingIDs: Set<AnyHashable> = []

    func present<Item: QuickLookPreviewable>(_ item: Item) {
        guard let preferredURL = item.quickLookPreferredURL ?? item.quickLookFallbackURL else {
            return
        }

        let id = item.quickLookID
        guard !loadingIDs.contains(id) else { return }
        loadingIDs.insert(id)

        Task {
            let preview = await AssetQuickLookStore.shared.previewURL(
                for: item,
                preferredURL: item.quickLookPreferredURL,
                fallbackURL: item.quickLookFallbackURL
            )

            await MainActor.run {
                if let preview {
                    self.previewURL = preview
                }
                self.loadingIDs.remove(id)
            }
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
    @StateObject private var presenter = QuickLookPresenter()

    func body(content: Content) -> some View {
        content
            .environment(\.quickLookPresenter, presenter)
            .quickLookPreview($presenter.previewURL)
    }
}

extension View {
    func quickLookPresenter() -> some View {
        modifier(QuickLookPresenterModifier())
    }
}
