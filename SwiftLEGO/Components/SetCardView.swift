import SwiftUI
import SwiftData

struct SetCardView: View {
    let brickSet: BrickSet

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(height: 140)

                if let url = brickSet.thumbnailURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .padding()
                        case .failure:
                            PlaceholderArtworkView(symbol: "shippingbox.fill")
                        @unknown default:
                            PlaceholderArtworkView(symbol: "questionmark")
                        }
                    }
                } else {
                    PlaceholderArtworkView(symbol: "shippingbox.fill")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(brickSet.setNumber)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                Text(brickSet.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text("\(brickSet.parts.count) parts configured")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 10)
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
