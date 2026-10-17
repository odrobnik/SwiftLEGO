import SwiftUI
import SwiftData
import BrickCore

struct OrderDetailView: View {
    let order: BrickOrder
    @State private var searchText: String = ""
    @State private var effectiveSearchText: String = ""

    var body: some View {
        OrderDetailContent(
            order: order,
            searchQuery: effectiveSearchText.isEmpty ? nil : effectiveSearchText
        )
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search order parts")
        .task(id: searchText) {
            await updateSearchQuery()
        }
        .quickLookPresenter()
        .toolbarTitleDisplayMode(.inline)
    }

    private func updateSearchQuery() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            effectiveSearchText = ""
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return
        }

        guard !Task.isCancelled else { return }
        effectiveSearchText = trimmed
    }
}

/// The order's parts for the debounced search query. Living below the view that owns
/// the search field, it re-runs when the query settles rather than on every keystroke.
private struct OrderDetailContent: View {
    @Query private var sets: [BrickSet]
    let order: BrickOrder
    /// The trimmed search query, or `nil` when not searching.
    let searchQuery: String?
    /// How many of each order part the wanted sets still miss; `nil` while computing.
    @State private var missingInSets: [MissingInSetsKey: Int]?

    var body: some View {
        // Sets the user excluded from the wanted list don't count as missing anything.
        let wantedSets = sets.filter { !$0.excludeFromWantedList }
        let setFilter = searchQuery.flatMap { SetSearchFilter(query: $0, sets: wantedSets) }

        Group {
            if let setFilter {
                OrderSetFilterList(order: order, filter: setFilter)
            } else {
                OrderPartsList(order: order, searchQuery: searchQuery, missingInSets: missingInSets)
            }
        }
        .navigationTitle(setFilter.map { "\($0.set.setNumber) \($0.set.name)" } ?? order.displayName)
        .task(id: MissingInSetsTaskKey(order: order, wantedSets: wantedSets)) {
            await loadMissingInSets(from: wantedSets)
        }
    }

    private func loadMissingInSets(from wantedSets: [BrickSet]) async {
        missingInSets = nil

        let orderKeys = Set(order.parts.map(MissingInSetsKey.init(orderPart:)))
        guard !orderKeys.isEmpty else {
            missingInSets = [:]
            return
        }

        var lookup: [MissingInSetsKey: Int] = [:]
        for set in wantedSets {
            Self.accumulateMissing(in: set, orderKeys: orderKeys, into: &lookup)
            await Task.yield()
            guard !Task.isCancelled else { return }
        }
        missingInSets = lookup
    }

    private static func accumulateMissing(
        in set: BrickSet,
        orderKeys: Set<MissingInSetsKey>,
        into lookup: inout [MissingInSetsKey: Int]
    ) {
        for part in set.parts {
            accumulateMissing(part: part, orderKeys: orderKeys, into: &lookup)
        }

        for minifigure in set.minifigures {
            let key = MissingInSetsKey(
                itemType: .minifigure,
                partID: SearchText.normalized(minifigure.identifier),
                colorID: ""
            )
            if orderKeys.contains(key) {
                let missing = max(minifigure.quantityNeeded - minifigure.quantityHave, 0)
                if missing > 0 {
                    lookup[key, default: 0] += missing
                }
            }
            for part in minifigure.parts {
                accumulateMissing(part: part, orderKeys: orderKeys, into: &lookup)
            }
        }
    }

    private static func accumulateMissing(
        part: Part,
        orderKeys: Set<MissingInSetsKey>,
        into lookup: inout [MissingInSetsKey: Int]
    ) {
        guard part.inventorySection != .extra else { return }

        let missing = part.missingQuantity
        if missing > 0 {
            let key = MissingInSetsKey(
                itemType: .part,
                partID: SearchText.normalized(part.partID),
                colorID: SearchText.normalized(part.colorID)
            )
            if orderKeys.contains(key) {
                lookup[key, default: 0] += missing
            }
        }

        // Subparts carry no `.set`/`.minifigure` backref, so they never appear in
        // `set.parts`/`minifigure.parts`. Recurse to count parts missing only as subparts.
        for child in part.subparts {
            accumulateMissing(part: child, orderKeys: orderKeys, into: &lookup)
        }
    }
}

/// What the "missing in sets" counts depend on: the order's parts and the wanted sets.
private struct MissingInSetsTaskKey: Equatable {
    let orderPartIDs: [PersistentIdentifier]
    let wantedSetIDs: Set<PersistentIdentifier>

    init(order: BrickOrder, wantedSets: [BrickSet]) {
        orderPartIDs = order.parts.map(\.persistentModelID)
        wantedSetIDs = Set(wantedSets.map(\.persistentModelID))
    }
}

private struct MissingInSetsKey: Hashable {
    let itemType: OrderPart.ItemType
    let partID: String
    let colorID: String
}

extension MissingInSetsKey {
    init(orderPart: OrderPart) {
        let partID = SearchText.normalized(orderPart.partID)
        if orderPart.itemType == .minifigure {
            self.init(itemType: .minifigure, partID: partID, colorID: "")
        } else {
            self.init(itemType: orderPart.itemType, partID: partID, colorID: SearchText.normalized(orderPart.colorID))
        }
    }
}

/// A search that names one of the wanted sets, like "75060 blue". It shows what that set
/// still misses from the order, filtered by the rest of the query.
private struct SetSearchFilter {
    let set: BrickSet
    let remainingQuery: String?

    /// Uses the first term that looks like a set number and matches one of `sets`;
    /// `nil` when no term does.
    init?(query: String, sets: [BrickSet]) {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)

        for (index, term) in terms.enumerated() {
            guard Self.isSetNumberCandidate(term),
                  let set = Self.set(matching: term, in: sets) else {
                continue
            }

            var remainingTerms = terms
            remainingTerms.remove(at: index)
            let remainingQuery = remainingTerms.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

            self.set = set
            self.remainingQuery = remainingQuery.isEmpty ? nil : remainingQuery
            return
        }

        return nil
    }

    /// Digits and dashes with at least four digits, like "75060" or "75060-1".
    private static func isSetNumberCandidate(_ term: String) -> Bool {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isNumber || $0 == "-" }) else { return false }
        return trimmed.count(where: \.isNumber) >= 4
    }

    private static func set(matching token: String, in sets: [BrickSet]) -> BrickSet? {
        let normalizedToken = SearchText.normalized(token)
        let strippedToken = SearchText.strippedSetNumber(normalizedToken)

        return sets.first { set in
            let setNumber = SearchText.normalized(set.setNumber)
            if setNumber == normalizedToken {
                return true
            }
            return !strippedToken.isEmpty && SearchText.strippedSetNumber(setNumber) == strippedToken
        }
    }
}

/// The order's parts matching the search, grouped by colour.
private struct OrderPartsList: View {
    @Query private var colors: [BrickColor]
    let order: BrickOrder
    let searchQuery: String?
    let missingInSets: [MissingInSetsKey: Int]?

    var body: some View {
        let groups = colorGroups()

        if groups.isEmpty {
            EmptyStateView(
                icon: "shippingbox",
                title: "No parts",
                message: searchQuery == nil ? "No parts to display." : "No parts match your search."
            )
        } else {
            List {
                ForEach(groups) { group in
                    Section(group.color) {
                        ForEach(group.rows) { row in
                            NavigationLink(value: row.route) {
                                OrderPartRowView(
                                    part: row.part,
                                    colorName: row.colorName,
                                    missingInSets: row.missingInSets
                                )
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func colorGroups() -> [OrderPartColorGroup] {
        let colorNames = Dictionary(
            colors.map { ($0.brickLinkColorID, $0.brickLinkName) },
            uniquingKeysWith: { first, _ in first }
        )
        let partQuery = searchQuery.flatMap(PartSearchQuery.init)

        let rows = order.parts.compactMap { part -> OrderPartRow? in
            let colorName = Self.resolvedColorName(for: part, colorNames: colorNames)

            if searchQuery != nil {
                guard let partQuery,
                      partQuery.matches(partID: part.partID, colorName: colorName, name: part.name) else {
                    return nil
                }
            }

            return OrderPartRow(
                part: part,
                colorName: colorName,
                missingInSets: missingInSets.map { $0[MissingInSetsKey(orderPart: part)] ?? 0 },
                route: OrderPartRoute(orderPart: part, searchQuery: searchQuery)
            )
        }

        return Dictionary(grouping: rows) { row in
            let trimmed = row.colorName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Unknown Color" : trimmed
        }
        .map { color, rows in
            let sortedRows = rows.sorted { lhs, rhs in
                let nameComparison = lhs.part.name.localizedCaseInsensitiveCompare(rhs.part.name)
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }
                return lhs.part.partID.localizedCaseInsensitiveCompare(rhs.part.partID) == .orderedAscending
            }
            return OrderPartColorGroup(color: color, rows: sortedRows)
        }
        .sorted { lhs, rhs in lhs.color.localizedCaseInsensitiveCompare(rhs.color) == .orderedAscending }
    }

    private static func resolvedColorName(for part: OrderPart, colorNames: [Int: String]) -> String {
        if part.itemType == .minifigure {
            return "Minifigure"
        }
        let trimmed = part.colorName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if let colorID = Int(part.colorID), let name = colorNames[colorID] {
            return name
        }
        if part.colorID.isEmpty {
            return "Unknown Color"
        }
        return "Color \(part.colorID)"
    }
}

/// An order part with everything its row shows, resolved once for the list.
private struct OrderPartRow: Identifiable {
    let part: OrderPart
    let colorName: String
    let missingInSets: Int?
    let route: OrderPartRoute

    var id: PersistentIdentifier { part.persistentModelID }
}

private struct OrderPartColorGroup: Identifiable {
    let color: String
    let rows: [OrderPartRow]

    var id: String { color }
}

/// The parts and minifigures of the set named in the search that are still missing and
/// that the order contains.
private struct OrderSetFilterList: View {
    let order: BrickOrder
    let filter: SetSearchFilter

    var body: some View {
        let orderQuantities = OrderQuantityLookup(order: order)
        let query = filter.remainingQuery.flatMap(PartSearchQuery.init)
        let partGroups = partsByColor(orderQuantities: orderQuantities, query: query)
        let minifigureRows = minifigures(orderQuantities: orderQuantities, query: query)

        if partGroups.isEmpty && minifigureRows.isEmpty {
            EmptyStateView(
                icon: "shippingbox",
                title: "No parts",
                message: "No missing parts from \(filter.set.setNumber) match your search."
            )
        } else {
            List {
                ForEach(partGroups, id: \.color) { group in
                    Section(group.color) {
                        ForEach(group.rows) { row in
                            PartRowNavigationWrapper(part: row.part, orderQuantity: row.orderQuantity)
                        }
                    }
                }

                if !minifigureRows.isEmpty {
                    Section("Minifigures") {
                        ForEach(minifigureRows) { row in
                            OrderMinifigureRowView(minifigure: row.minifigure, orderQuantity: row.orderQuantity)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.isFilteringMissingParts, true)
        }
    }

    private func partsByColor(
        orderQuantities: OrderQuantityLookup,
        query: PartSearchQuery?
    ) -> [(color: String, rows: [SetFilterPartRow])] {
        let rows = filter.set.parts.compactMap { part -> SetFilterPartRow? in
            guard part.inventorySection != .extra, Self.hasMissingHierarchy(part) else { return nil }

            let quantityInOrder = orderQuantities.quantity(of: part)
            guard quantityInOrder > 0 else { return nil }

            if let query, !Self.matchesHierarchy(of: part, query: query) {
                return nil
            }
            return SetFilterPartRow(part: part, orderQuantity: quantityInOrder)
        }

        return Dictionary(grouping: rows) { row in
            let trimmed = row.part.colorName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Unknown Color" : trimmed
        }
        .map { color, rows in
            let sortedRows = rows.sorted { lhs, rhs in
                Part.subpartSortComparator(lhs.part, rhs.part)
            }
            return (color: color, rows: sortedRows)
        }
        .sorted { lhs, rhs in lhs.color.localizedCaseInsensitiveCompare(rhs.color) == .orderedAscending }
    }

    private func minifigures(
        orderQuantities: OrderQuantityLookup,
        query: PartSearchQuery?
    ) -> [SetFilterMinifigureRow] {
        let queryTokens = filter.remainingQuery.map(SearchText.tokens(from:)) ?? []

        return filter.set.minifigures
            .compactMap { minifigure -> SetFilterMinifigureRow? in
                guard Self.hasMissingHierarchy(minifigure) else { return nil }

                let quantityInOrder = orderQuantities.quantity(of: minifigure)
                guard quantityInOrder > 0 else { return nil }

                if let query {
                    let matchesFigure = Self.matches(minifigure, tokens: queryTokens)
                    guard matchesFigure || minifigure.parts.contains(where: { Self.matchesHierarchy(of: $0, query: query) }) else {
                        return nil
                    }
                }
                return SetFilterMinifigureRow(minifigure: minifigure, orderQuantity: quantityInOrder)
            }
            .sorted { lhs, rhs in
                if lhs.minifigure.name != rhs.minifigure.name {
                    return lhs.minifigure.name.localizedCaseInsensitiveCompare(rhs.minifigure.name) == .orderedAscending
                }
                return lhs.minifigure.identifier.localizedCaseInsensitiveCompare(rhs.minifigure.identifier) == .orderedAscending
            }
    }

    private static func matchesHierarchy(of part: Part, query: PartSearchQuery) -> Bool {
        let colorName = part.colorName.isEmpty ? "Unknown Color" : part.colorName
        if query.matches(partID: part.partID, colorName: colorName, name: part.name) {
            return true
        }
        return part.subparts.contains { matchesHierarchy(of: $0, query: query) }
    }

    private static func matches(_ minifigure: Minifigure, tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return true }

        let figureTokens = Set(SearchText.tokens(from: "\(minifigure.identifier) \(minifigure.name)"))
        return tokens.allSatisfy { token in
            figureTokens.contains { $0.contains(token) }
        }
    }

    private static func hasMissingHierarchy(_ part: Part) -> Bool {
        part.quantityHave < part.quantityNeeded || part.subparts.contains { hasMissingHierarchy($0) }
    }

    private static func hasMissingHierarchy(_ minifigure: Minifigure) -> Bool {
        minifigure.quantityHave < minifigure.quantityNeeded || minifigure.parts.contains { hasMissingHierarchy($0) }
    }
}

/// How many of each part and minifigure the order contains.
private struct OrderQuantityLookup {
    private struct PartColorKey: Hashable {
        let partID: String
        let colorID: String
    }

    private var partQuantities: [PartColorKey: Int] = [:]
    private var minifigureQuantities: [String: Int] = [:]

    init(order: BrickOrder) {
        for part in order.parts {
            switch part.itemType {
            case .minifigure:
                minifigureQuantities[SearchText.normalized(part.partID), default: 0] += part.quantity
            case .part:
                let key = PartColorKey(
                    partID: SearchText.normalized(part.partID),
                    colorID: SearchText.normalized(part.colorID)
                )
                partQuantities[key, default: 0] += part.quantity
            }
        }
    }

    func quantity(of part: Part) -> Int {
        let key = PartColorKey(
            partID: SearchText.normalized(part.partID),
            colorID: SearchText.normalized(part.colorID)
        )
        return partQuantities[key] ?? 0
    }

    func quantity(of minifigure: Minifigure) -> Int {
        minifigureQuantities[SearchText.normalized(minifigure.identifier)] ?? 0
    }
}

private struct SetFilterPartRow: Identifiable {
    let part: Part
    let orderQuantity: Int

    var id: PersistentIdentifier { part.persistentModelID }
}

private struct SetFilterMinifigureRow: Identifiable {
    let minifigure: Minifigure
    let orderQuantity: Int

    var id: PersistentIdentifier { minifigure.persistentModelID }
}

private struct OrderPartRowView: View {
    let part: OrderPart
    let colorName: String
    let missingInSets: Int?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            OrderPartThumbnail(part: part)

            VStack(alignment: .leading, spacing: 6) {
                Text(displayName)
                    .font(.headline)

                Text("\(part.partID) • \(colorName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(part.quantity) in order")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                if let missingInSets {
                    Text("^[\(missingInSets) missing in sets](inflect: true)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if part.quantity > 0 {
                    Text("Missing in sets...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var displayName: String {
        let trimmed = part.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Part \(part.partID)" : trimmed
    }
}

private struct OrderPartThumbnail: View {
    @Environment(\.modelContext) private var modelContext
    let part: OrderPart

    var body: some View {
        QuickLookThumbnail(item: part) {
            if let url = part.imageURL {
                ThumbnailImage(url: url, replacementURL: {
                    await PartImageHealing.healThumbnail(of: part, in: modelContext)
                }) { phase in
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
                            ThumbnailPlaceholder(systemImage: "cube.transparent", width: 80, height: 60)
                            if let retry = state.retry {
                                Button("Retry", action: retry)
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .background(.white)
            } else {
                ThumbnailPlaceholder(systemImage: "cube.transparent", width: 80, height: 60)
            }
        }
    }
}

private struct OrderMinifigureRowView: View {
    @Environment(\.modelContext) private var modelContext
    let minifigure: Minifigure
    var orderQuantity: Int? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            MinifigureThumbnailView(url: minifigure.imageURL, size: 56)

            VStack(alignment: .leading, spacing: 6) {
                Text(minifigure.displayName(includeInstanceSuffix: true))
                    .font(.headline)

                Text(minifigure.displayIdentifier(includeInstanceSuffix: true))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .center, spacing: 4) {
                Text("\(minifigure.quantityHave) of \(minifigure.quantityNeeded)")
                    .font(.title3.bold())
                    .contentTransition(.numericText())

                Stepper("", value: quantityHave, in: 0...max(0, minifigure.quantityNeeded))
                    .labelsHidden()

                if let orderQuantity, orderQuantity > 0 {
                    Text("^[\(orderQuantity) minifigure](inflect: true) in order")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 80, idealWidth: 100)
        }
        .padding(.vertical, 6)
    }

    private var quantityHave: Binding<Int> {
        Binding(
            get: { minifigure.quantityHave },
            set: { updateQuantity(to: $0) }
        )
    }

    private func updateQuantity(to newValue: Int) {
        let clamped = max(0, min(newValue, minifigure.quantityNeeded))
        guard clamped != minifigure.quantityHave else { return }

        withAnimation {
            minifigure.quantityHave = clamped
            minifigure.synchronizeParts(to: clamped)
            try? modelContext.save()
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
