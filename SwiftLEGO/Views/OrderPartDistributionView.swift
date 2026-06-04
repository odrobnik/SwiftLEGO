import SwiftUI
import SwiftData
import BrickCore

struct OrderPartDistributionView: View {
    let orderPart: OrderPart
    let searchQuery: String?
    @Query private var matchingParts: [Part]
    @Query private var matchingMinifigures: [Minifigure]
    @State private var cachedMatches: [OrderPartMatch]?
    @State private var cachedMinifigureMatches: [OrderMinifigureMatch]?

    init(orderPart: OrderPart, searchQuery: String? = nil) {
        self.orderPart = orderPart
        self.searchQuery = searchQuery
        let partID = orderPart.partID
        let colorID = orderPart.colorID
        _matchingParts = Query(filter: #Predicate<Part> { part in
            part.partID == partID &&
            part.colorID == colorID &&
            part.quantityNeeded > 0 &&
            part.quantityHave < part.quantityNeeded &&
            part.inventorySectionRawValue != "extra"
        })
        _matchingMinifigures = Query(filter: #Predicate<Minifigure> { minifigure in
            minifigure.identifier == partID &&
            minifigure.quantityNeeded > 0 &&
            minifigure.quantityHave < minifigure.quantityNeeded
        })
    }

    private var matchingPartIDs: [PersistentIdentifier] {
        matchingParts.map(\.persistentModelID)
    }

    private var matchingMinifigureIDs: [PersistentIdentifier] {
        matchingMinifigures.map(\.persistentModelID)
    }

    private func computeMatches() -> [OrderPartMatch] {
        matchingParts.compactMap { part in
            guard let set = part.set ?? part.minifigure?.set else {
                return nil
            }
            guard !set.excludeFromWantedList else { return nil }
            return OrderPartMatch(
                id: part.persistentModelID,
                set: set,
                part: part,
                owningMinifigure: part.minifigure,
                parentChain: parentChain(for: part)
            )
        }
        .sorted { lhs, rhs in
            let lhsList = lhs.set.collection?.name ?? ""
            let rhsList = rhs.set.collection?.name ?? ""
            if lhsList != rhsList {
                return lhsList.localizedCaseInsensitiveCompare(rhsList) == .orderedAscending
            }
            if lhs.set.setNumber != rhs.set.setNumber {
                return lhs.set.setNumber.localizedCaseInsensitiveCompare(rhs.set.setNumber) == .orderedAscending
            }
            if lhs.part.name != rhs.part.name {
                return lhs.part.name.localizedCaseInsensitiveCompare(rhs.part.name) == .orderedAscending
            }
            return lhs.part.partID.localizedCaseInsensitiveCompare(rhs.part.partID) == .orderedAscending
        }
    }

    private func computeMinifigureMatches() -> [OrderMinifigureMatch] {
        matchingMinifigures.compactMap { minifigure in
            guard let set = minifigure.set else { return nil }
            guard !set.excludeFromWantedList else { return nil }
            return OrderMinifigureMatch(
                id: minifigure.persistentModelID,
                set: set,
                minifigure: minifigure
            )
        }
        .sorted { lhs, rhs in
            let lhsList = lhs.set.collection?.name ?? ""
            let rhsList = rhs.set.collection?.name ?? ""
            if lhsList != rhsList {
                return lhsList.localizedCaseInsensitiveCompare(rhsList) == .orderedAscending
            }
            if lhs.set.setNumber != rhs.set.setNumber {
                return lhs.set.setNumber.localizedCaseInsensitiveCompare(rhs.set.setNumber) == .orderedAscending
            }
            return lhs.minifigure.identifier.localizedCaseInsensitiveCompare(rhs.minifigure.identifier) == .orderedAscending
        }
    }

    var body: some View {
        Group {
            switch orderPart.itemType {
            case .part:
                let matches = cachedMatches ?? computeMatches()
                if matches.isEmpty {
                    EmptyStateView(
                        icon: "cube.transparent",
                        title: "No Missing Parts",
                        message: "All sets already have this part."
                    )
                } else {
                    List {
                        Section {
                            ForEach(matches) { match in
                                NavigationLink(value: searchResult(for: match)) {
                                    PartSearchResultRow(
                                        set: match.set,
                                        part: match.part,
                                        owningMinifigure: match.owningMinifigure,
                                        parentChain: match.parentChain
                                    )
                                }
                            }
                        } header: {
                            OrderPartHeaderView(
                                detail: "\(orderPart.partID) • \(displayColorName)"
                            )
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            case .minifigure:
                let minifigureMatches = cachedMinifigureMatches ?? computeMinifigureMatches()
                if minifigureMatches.isEmpty {
                    EmptyStateView(
                        icon: "person.fill",
                        title: "No Missing Minifigures",
                        message: "All sets already have this minifigure."
                    )
                } else {
                    List {
                        Section {
                            ForEach(minifigureMatches) { match in
                                NavigationLink(value: searchResult(for: match)) {
                                    MinifigureSearchResultRow(
                                        set: match.set,
                                        minifigure: match.minifigure
                                    )
                                }
                            }
                        } header: {
                            OrderPartHeaderView(
                                detail: "Minifigure • \(orderPart.partID)"
                            )
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
        }
        .task(id: matchingPartIDs) {
            cachedMatches = computeMatches()
        }
        .task(id: matchingMinifigureIDs) {
            cachedMinifigureMatches = computeMinifigureMatches()
        }
        .navigationTitle(displayName)
        .toolbarTitleDisplayMode(.inline)
    }

    private var displayName: String {
        let trimmed = orderPart.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Part \(orderPart.partID)" : trimmed
    }

    private var displayColorName: String {
        if orderPart.itemType == .minifigure {
            return "Minifigure"
        }
        let trimmed = orderPart.colorName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if orderPart.colorID.isEmpty {
            return "Unknown Color"
        }
        return "Color \(orderPart.colorID)"
    }

    private func parentChain(for part: Part) -> [Part] {
        var chain: [Part] = []
        var current = part.parentPart

        while let node = current {
            chain.append(node)
            current = node.parentPart
        }

        return chain.reversed()
    }

    private func searchResult(for match: OrderPartMatch) -> SearchResult {
        SearchResult(
            set: match.set,
            searchQuery: forwardedSearchQuery,
            section: match.part.inventorySection
        )
    }

    private func searchResult(for match: OrderMinifigureMatch) -> SearchResult {
        SearchResult(
            set: match.set,
            searchQuery: forwardedSearchQuery,
            section: .regular
        )
    }

    private var forwardedSearchQuery: String {
        let trimmed = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed
    }
}

private struct OrderPartMatch: Identifiable {
    let id: PersistentIdentifier
    let set: BrickSet
    let part: Part
    let owningMinifigure: Minifigure?
    let parentChain: [Part]
}

private struct OrderMinifigureMatch: Identifiable {
    let id: PersistentIdentifier
    let set: BrickSet
    let minifigure: Minifigure
}

private struct OrderPartHeaderView: View {
    let detail: String

    var body: some View {
        Text(detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .textCase(nil)
            .padding(.vertical, 4)
    }
}

#Preview("Order Part Distribution") {
    let container = SwiftLEGOModelContainer.preview
    let context = ModelContext(container)
    let orderPart = OrderPart(partID: "3001", name: "Brick 2 x 4", colorID: "1", colorName: "White", quantity: 4)
    context.insert(orderPart)

    return NavigationStack {
        OrderPartDistributionView(orderPart: orderPart, searchQuery: "3001")
    }
    .modelContainer(container)
}
