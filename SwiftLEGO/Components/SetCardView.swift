import SwiftUI
import SwiftData
import BrickCore

struct SetCardView: View {
    let brickSet: BrickSet

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.white))
                   

                if let url = brickSet.thumbnailURL {
                    ThumbnailImage(url: url) { phase in
                        switch phase {
                        case .empty, .loading:
                            ProgressView()
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        case .failure(let state):
                            VStack(spacing: 12) {
                                PlaceholderArtworkView(symbol: "shippingbox.fill")
                                Button("Retry") {
                                    state.retry()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                } else {
                    PlaceholderArtworkView(symbol: "shippingbox.fill")
                }
            }
            .frame(height: 240)
            .clipped()

            VStack(alignment: .leading, spacing: 6) {
                Text(brickSet.setNumber)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                Text(brickSet.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.primary.opacity(0.15), radius: 14, x: 0, y: 10)
        }
    }
}

private struct PlaceholderArtworkView: View {
    let symbol: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Thumbnail Unavailable")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    let container = SwiftLEGOModelContainer.preview
    let set = try! ModelContext(container)
        .fetch(FetchDescriptor<BrickSet>())
        .first!

    return SetCardView(brickSet: set)
        .frame(width: 260)
        .modelContainer(container)
}
