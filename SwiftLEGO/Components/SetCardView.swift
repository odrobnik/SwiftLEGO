import SwiftUI
import SwiftData

struct SetCardView: View {
    let brickSet: BrickSet
    @State private var thumbnailReloadID = UUID()
    @State private var thumbnailRetryCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)

                if let url = brickSet.thumbnailURL {
                    AsyncImage(url: url, transaction: Transaction(animation: .default)) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .onAppear {
                                    if thumbnailRetryCount != 0 {
                                        thumbnailRetryCount = 0
                                    }
                                }
                        case .failure(let error):
                            PlaceholderArtworkView(symbol: "shippingbox.fill")
                                .onAppear {
                                    scheduleThumbnailRetry(for: error, url: url)
                                }
                        @unknown default:
                            PlaceholderArtworkView(symbol: "questionmark")
                        }
                    }
                    .id(thumbnailReloadID)
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
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 10)
        }
    }

    private func scheduleThumbnailRetry(for error: Error, url: URL) {
        guard shouldRetryThumbnail(for: error) else {
            #if DEBUG
            print("\(url.absoluteString) - \(error.localizedDescription)")
            #endif
            return
        }

        let attempt = thumbnailRetryCount

        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)

            await MainActor.run {
                guard thumbnailRetryCount == attempt else { return }
                thumbnailRetryCount += 1
                thumbnailReloadID = UUID()
            }
        }
    }

    private func shouldRetryThumbnail(for error: Error) -> Bool {
        guard thumbnailRetryCount < 3 else { return false }

        if let urlError = error as? URLError {
            return urlError.code == .cancelled
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == URLError.cancelled.rawValue
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
