import SwiftUI
import SwiftData
import BrickCore

struct OrderDetailView: View {
    @Query private var colors: [BrickColor]
    @Bindable var order: BrickOrder
    @State private var searchText: String = ""

    private var filteredParts: [OrderPart] {
        guard let query = normalizedSearchQuery else {
            return order.parts
        }
        return order.parts.filter { part in
            let searchable = "\(part.partID) \(part.name) \(resolvedColorName(for: part)) \(part.itemType.rawValue)"
            return searchable.lowercased().contains(query)
        }
    }

    private var partsByColor: [(color: String, parts: [OrderPart])] {
        let grouped = Dictionary(grouping: filteredParts) { part in
            normalizeColorName(resolvedColorName(for: part))
        }

        return grouped
            .map { key, value in
                let sortedParts = value.sorted { lhs, rhs in
                    let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                    if nameComparison != .orderedSame {
                        return nameComparison == .orderedAscending
                    }
                    return lhs.partID.localizedCaseInsensitiveCompare(rhs.partID) == .orderedAscending
                }
                return (color: key, parts: sortedParts)
            }
            .sorted { lhs, rhs in lhs.color.localizedCaseInsensitiveCompare(rhs.color) == .orderedAscending }
    }

    private var normalizedSearchQuery: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    var body: some View {
        Group {
            if partsByColor.isEmpty {
                EmptyStateView(
                    icon: "shippingbox",
                    title: "No parts",
                    message: normalizedSearchQuery == nil ? "No parts to display." : "No parts match your search."
                )
            } else {
                List {
                    ForEach(partsByColor, id: \.color) { group in
                        Section(group.color) {
                            ForEach(group.parts) { part in
                                NavigationLink {
                                    OrderPartDistributionView(orderPart: part)
                                } label: {
                                    OrderPartRowView(
                                        part: part,
                                        colorName: resolvedColorName(for: part)
                                    )
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search order parts")
        .navigationTitle(order.displayName)
        .toolbarTitleDisplayMode(.inline)
    }

    private func resolvedColorName(for part: OrderPart) -> String {
        if part.itemType == .minifigure {
            return "Minifigure"
        }
        let trimmed = part.colorName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if let colorID = Int(part.colorID),
           let match = colors.first(where: { $0.brickLinkColorID == colorID }) {
            return match.brickLinkName
        }
        if part.colorID.isEmpty {
            return "Unknown Color"
        }
        return "Color \(part.colorID)"
    }

    private func normalizeColorName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown Color" : trimmed
    }
}

private struct OrderPartRowView: View {
    let part: OrderPart
    let colorName: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                Text(displayName)
                    .font(.headline)

                Text("\(part.partID) • \(colorName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("^[\(part.quantity) \(part.itemType == .minifigure ? "minifigure" : "part")](inflect: true)")
                .font(.title3.bold())
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
    }

    private var displayName: String {
        let trimmed = part.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Part \(part.partID)" : trimmed
    }

    @ViewBuilder
    private var thumbnail: some View {
        QuickLookThumbnail(item: part) {
            if let url = part.imageURL {
                ThumbnailImage(url: url) { phase in
                    switch phase {
                    case .empty, .loading:
                        ProgressView()
                            .frame(width: 80, height: 60)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    case .failure(let state):
                        VStack(spacing: 6) {
                            placeholder
                            Button("Retry") {
                                state.retry()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .background(.white)
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemFill))
            .frame(width: 80, height: 60)
            .overlay {
                Image(systemName: "cube.transparent")
                    .foregroundStyle(.secondary)
            }
    }
}

#Preview("Order Detail") {
    let container = SwiftLEGOModelContainer.preview
    let context = ModelContext(container)
    let order = BrickOrder(name: "Order #12345", parts: [
        OrderPart(partID: "3001", name: "Brick 2 x 4", colorID: "1", colorName: "White", quantity: 12),
        OrderPart(partID: "3020", name: "Plate 2 x 4", colorID: "5", colorName: "Red", quantity: 4)
    ])
    context.insert(order)

    return NavigationStack {
        OrderDetailView(order: order)
    }
    .modelContainer(container)
}
