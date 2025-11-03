import SwiftUI

struct QuickLookThumbnail<Item: QuickLookPreviewable, Content: View>: View {
    enum Gesture {
        case tap
        case longPress
    }

    @Environment(\.quickLookPresenter) private var presenter

    private let item: Item
    private let overlayAlignment: Alignment
    private let gesture: Gesture
    private let content: Content

    init(
        item: Item,
        overlayAlignment: Alignment = .bottomTrailing,
        gesture: Gesture = .longPress,
        @ViewBuilder content: () -> Content
    ) {
        self.item = item
        self.overlayAlignment = overlayAlignment
        self.gesture = gesture
        self.content = content()
    }

    var body: some View {
        Group {
            if let presenter {
                let isLoading = presenter.isLoading(item)
                interactiveContent(isLoading: isLoading) {
                    presenter.present(item)
                }
            } else {
                content
            }
        }
    }

    @ViewBuilder
    private func interactiveContent(
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let base = content
            .contentShape(Rectangle())
            .overlay(alignment: overlayAlignment) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(4)
                        .background(.thinMaterial, in: Capsule())
                }
            }
            .accessibilityAddTraits(.isButton)

        switch gesture {
        case .tap:
            base.onTapGesture(perform: action)
        case .longPress:
            base.onLongPressGesture(perform: action)
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
    private let item: Item
    private let label: () -> LabelContent
    @Environment(\.quickLookPresenter) private var presenter

    init(item: Item, @ViewBuilder label: @escaping () -> LabelContent) {
        self.item = item
        self.label = label
    }

    var body: some View {
        Button {
            presenter?.present(item)
        } label: {
            label()
        }
    }
}
