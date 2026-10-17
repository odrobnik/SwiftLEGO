import SwiftUI

/// A square minifigure thumbnail with a retry button when loading fails for a
/// reason that retrying can fix.
struct MinifigureThumbnailView: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        if let url {
            ThumbnailImage(url: url) { phase in
                switch phase {
                case .empty, .loading:
                    ProgressView()
                        .frame(width: size, height: size)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                case .failure(let state):
                    VStack(spacing: 6) {
                        ThumbnailPlaceholder(systemImage: "person.fill", width: size, height: size)
                        if let retry = state.retry {
                            Button("Retry", action: retry)
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .background(.white)
        } else {
            ThumbnailPlaceholder(systemImage: "person.fill", width: size, height: size)
        }
    }
}
