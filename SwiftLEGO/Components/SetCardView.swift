import SwiftUI
import SwiftData
import BrickCore

private let regularSectionRawValue = Part.InventorySection.regular.rawValue

struct SetCardView: View {
    let brickSet: BrickSet
    @Query private var regularRootParts: [Part]
    @Query private var minifigures: [Minifigure]

    init(brickSet: BrickSet) {
        self.brickSet = brickSet
        let setID = brickSet.persistentModelID
        _regularRootParts = Query(
            filter: #Predicate { part in
                part.set?.persistentModelID == setID &&
                part.parentPart == nil &&
                part.inventorySectionRawValue == regularSectionRawValue
            }
        )
        _minifigures = Query(
            filter: #Predicate { figure in
                figure.set?.persistentModelID == setID
            }
        )
    }

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
                HStack(spacing: 6) {
                    Text(brickSet.setNumber)
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)

                    if let completionText {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        completionText
                    }
                }

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

    private var completionText: Text? {
        guard let percentage = completionPercentage else { return nil }
        let formatted = percentage.formatted(.percent.precision(.fractionLength(0)))
        return Text(formatted)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var completionPercentage: Double? {
        let totals = completionTotals()
        guard totals.needed > 0 else { return nil }
        return min(1, max(0, Double(totals.have) / Double(totals.needed)))
    }

    private func completionTotals() -> (have: Int, needed: Int) {
        var totals = (have: 0, needed: 0)

        func accumulate(have: Int, needed: Int) {
            guard needed > 0 else { return }
            totals.needed += needed
            totals.have += min(max(have, 0), needed)
        }

        for part in regularRootParts {
            accumulate(have: part.quantityHave, needed: part.quantityNeeded)
        }

        for figure in minifigures {
            accumulate(have: figure.quantityHave, needed: figure.quantityNeeded)
        }

        return totals
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
