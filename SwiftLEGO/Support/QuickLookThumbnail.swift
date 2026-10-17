import SwiftUI

struct QuickLookThumbnail<Item: QuickLookPreviewable, Content: View>: View {
    enum Gesture {
        case tap
        case longPress
    }

    @Environment(\.quickLookPresenter) private var presenter

    let item: Item
    var overlayAlignment: Alignment = .bottomTrailing
    var gesture: Gesture = .longPress
    @ViewBuilder let content: Content

    var body: some View {
        if let presenter {
            let base = content
                .contentShape(Rectangle())
                .overlay(alignment: overlayAlignment) {
                    if presenter.isLoading(item) {
                        ProgressView()
                            .controlSize(.small)
                            .padding(4)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
                .accessibilityAddTraits(.isButton)

            switch gesture {
            case .tap:
                base.onTapGesture {
                    presenter.present(item)
                }
            case .longPress:
                base.onLongPressGesture {
                    presenter.present(item)
                }
            }
        } else {
            content
        }
    }
}

extension View {
    func quickLookThumbnail<Item: QuickLookPreviewable>(
        for item: Item,
        overlayAlignment: Alignment = .bottomTrailing,
        gesture: QuickLookThumbnail<Item, Self>.Gesture = .longPress
    ) -> some View {
        QuickLookThumbnail(item: item, overlayAlignment: overlayAlignment, gesture: gesture) {
            self
        }
    }
}

struct QuickLookMenuButton<Item: QuickLookPreviewable, LabelContent: View>: View {
    @Environment(\.quickLookPresenter) private var presenter
    let item: Item
    @ViewBuilder let label: () -> LabelContent

    var body: some View {
        Button {
            presenter?.present(item)
        } label: {
            label()
        }
    }
}
