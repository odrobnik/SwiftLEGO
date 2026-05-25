import SwiftUI
import SwiftData
import BrickCore

struct OrderDetailView: View {
    @Query private var colors: [BrickColor]
    @Query private var sets: [BrickSet]
    @Bindable var order: BrickOrder
    @State private var searchText: String = ""
    @State private var effectiveSearchText: String = ""
    @State private var missingInSetsLookup: [MissingInSetsKey: Int] = [:]
    @State private var hasComputedMissingInSets: Bool = false
    @State private var cachedOrderPartsByColor: [OrderPartColorGroup]?

    private var filteredParts: [OrderPart] {
        guard let query = normalizedSearchQuery else {
            return order.parts
        }
        if let setFilter = setSearchFilter {
            let lookup = missingLookup(for: setFilter.set)
            return order.parts.filter { part in
                guard matchesSetFilter(part, lookup: lookup) else { return false }
                guard let remainingQuery = setFilter.remainingQuery else { return true }
                return matchesOrderPart(part, query: remainingQuery)
            }
        }
        return order.parts.filter { part in
            matchesOrderPart(part, query: query)
        }
    }

    private func computeOrderPartsByColor() -> [OrderPartColorGroup] {
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
                return OrderPartColorGroup(color: key, parts: sortedParts)
            }
            .sorted { lhs, rhs in lhs.color.localizedCaseInsensitiveCompare(rhs.color) == .orderedAscending }
    }

    private var orderPartsByColorCacheKey: OrderPartsByColorCacheKey {
        OrderPartsByColorCacheKey(
            searchText: effectiveSearchText,
            hasSetFilter: setSearchFilter != nil,
            orderPartIDs: order.parts.map(\.persistentModelID),
            colorCount: colors.count
        )
    }

    private var setFilterPartsByColor: [(color: String, parts: [SetFilterPartRow])] {
        guard let setFilter = setSearchFilter else { return [] }
        let orderLookup = orderQuantityLookup
        let filtered = setFilter.set.parts.compactMap { part -> SetFilterPartRow? in
            guard part.inventorySection != .extra else { return nil }
            guard hasMissingHierarchy(part) else { return nil }
            let quantityInOrder = orderQuantity(for: part, lookup: orderLookup)
            guard quantityInOrder > 0 else { return nil }
            guard let query = setFilter.remainingQuery else {
                return SetFilterPartRow(part: part, orderQuantity: quantityInOrder)
            }
            guard matchesPartHierarchy(part, query: query) else { return nil }
            return SetFilterPartRow(part: part, orderQuantity: quantityInOrder)
        }

        let grouped = Dictionary(grouping: filtered) { row in
            normalizeColorName(row.part.colorName)
        }

        return grouped
            .map { key, value in
                let sortedParts = value.sorted { lhs, rhs in
                    Part.subpartSortComparator(lhs.part, rhs.part)
                }
                return (color: key, parts: sortedParts)
            }
            .sorted { lhs, rhs in lhs.color.localizedCaseInsensitiveCompare(rhs.color) == .orderedAscending }
    }

    private var setFilterMinifigures: [SetFilterMinifigureRow] {
        guard let setFilter = setSearchFilter else { return [] }
        let orderLookup = orderQuantityLookup
        let filtered = setFilter.set.minifigures.compactMap { minifigure -> SetFilterMinifigureRow? in
            guard hasMissingHierarchy(minifigure) else { return nil }
            let quantityInOrder = orderQuantity(for: minifigure, lookup: orderLookup)
            guard quantityInOrder > 0 else { return nil }
            guard let query = setFilter.remainingQuery else {
                return SetFilterMinifigureRow(minifigure: minifigure, orderQuantity: quantityInOrder)
            }
            guard matchesMinifigureSearch(minifigure, query: query) ||
                    minifigure.parts.contains(where: { matchesPartHierarchy($0, query: query) }) else { return nil }
            return SetFilterMinifigureRow(minifigure: minifigure, orderQuantity: quantityInOrder)
        }

        return filtered.sorted { lhs, rhs in
            if lhs.minifigure.name != rhs.minifigure.name {
                return lhs.minifigure.name.localizedCaseInsensitiveCompare(rhs.minifigure.name) == .orderedAscending
            }
            return lhs.minifigure.identifier.localizedCaseInsensitiveCompare(rhs.minifigure.identifier) == .orderedAscending
        }
    }

    private var normalizedSearchQuery: String? {
        let trimmed = effectiveSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var forwardedSearchQuery: String? {
        if let remainingQuery = setSearchFilter?.remainingQuery {
            return remainingQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : remainingQuery
        }
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        Group {
            let partsByColor = cachedOrderPartsByColor ?? computeOrderPartsByColor()
            if (setSearchFilter == nil && partsByColor.isEmpty) ||
                (setSearchFilter != nil && setFilterPartsByColor.isEmpty && setFilterMinifigures.isEmpty) {
                EmptyStateView(
                    icon: "shippingbox",
                    title: "No parts",
                    message: emptyStateMessage
                )
            } else {
                List {
                    if setSearchFilter == nil {
                        ForEach(partsByColor) { group in
                            Section(group.color) {
                                ForEach(group.parts) { part in
                                    let missingInSetsValue = hasComputedMissingInSets
                                        ? missingInSets(for: part, lookup: missingInSetsLookup)
                                        : nil
                                    NavigationLink(value: OrderPartRoute(orderPart: part, searchQuery: forwardedSearchQuery)) {
                                        OrderPartRowView(
                                            part: part,
                                            colorName: resolvedColorName(for: part),
                                            missingInSets: missingInSetsValue
                                        )
                                    }
                                }
                            }
                        }
            } else {
                        ForEach(setFilterPartsByColor, id: \.color) { group in
                            Section(group.color) {
                                ForEach(group.parts) { row in
                                    PartRowNavigationWrapper(
                                        part: row.part,
                                        isFilteringMissing: true,
                                        orderQuantity: row.orderQuantity
                                    )
                                }
                            }
                        }

                        if !setFilterMinifigures.isEmpty {
                            Section("Minifigures") {
                                ForEach(setFilterMinifigures) { row in
                                    OrderMinifigureRowView(
                                        minifigure: row.minifigure,
                                        orderQuantity: row.orderQuantity
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
        .task(id: searchText) {
            await updateSearchQuery()
        }
        .task(id: missingInSetsTaskID) {
            await loadMissingInSetsLookup()
        }
        .task(id: orderPartsByColorCacheKey) {
            cachedOrderPartsByColor = computeOrderPartsByColor()
        }
        .navigationTitle(order.displayName)
        .toolbarTitleDisplayMode(.inline)
    }

    private var emptyStateMessage: String {
        if let setFilter = setSearchFilter {
            return "No missing parts from \(setFilter.set.setNumber) match your search."
        }
        return normalizedSearchQuery == nil ? "No parts to display." : "No parts match your search."
    }

    private struct OrderPartColorGroup: Identifiable {
        let color: String
        let parts: [OrderPart]

        var id: String { color }
    }

    private struct OrderPartsByColorCacheKey: Equatable {
        let searchText: String
        let hasSetFilter: Bool
        let orderPartIDs: [PersistentIdentifier]
        let colorCount: Int
    }

    private struct SetSearchFilter {
        let set: BrickSet
        let remainingQuery: String?
    }

    private struct MissingPartKey: Hashable {
        let partID: String
        let colorID: String
    }

    private struct MissingLookup {
        let partKeys: Set<MissingPartKey>
        let minifigureIDs: Set<String>
    }

    private struct MissingInSetsKey: Hashable {
        let itemType: OrderPart.ItemType
        let partID: String
        let colorID: String
    }

    private struct OrderQuantityLookup {
        let partQuantities: [MissingPartKey: Int]
        let minifigureQuantities: [String: Int]
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

    private var setSearchFilter: SetSearchFilter? {
        let trimmed = effectiveSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let terms = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        for (index, term) in terms.enumerated() {
            guard let token = setTokenCandidate(from: term) else { continue }
            guard let setMatch = matchSet(for: token) else { continue }

            var remainingTerms = terms
            remainingTerms.remove(at: index)
            let remainingQuery = remainingTerms.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return SetSearchFilter(
                set: setMatch,
                remainingQuery: remainingQuery.isEmpty ? nil : remainingQuery
            )
        }

        return nil
    }

    private func setTokenCandidate(from term: String) -> String? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.allSatisfy({ $0.isNumber || $0 == "-" }) else { return nil }
        let digitCount = trimmed.filter(\.isNumber).count
        guard digitCount >= 4 else { return nil }
        return trimmed
    }

    private func matchSet(for token: String) -> BrickSet? {
        let normalizedToken = normalized(token)
        let strippedToken = normalizeSetNumber(normalizedToken)

        return sets.first { set in
            let normalizedSetNumber = normalized(set.setNumber)
            if normalizedSetNumber == normalizedToken {
                return true
            }
            let strippedSetNumber = normalizeSetNumber(normalizedSetNumber)
            if !strippedToken.isEmpty, strippedSetNumber == strippedToken {
                return true
            }
            return false
        }
    }

    private func normalizeSetNumber(_ number: String) -> String {
        number.split(separator: "-").first.map(String.init) ?? number
    }

    private var missingInSetsTaskID: String {
        let orderToken = order.parts.map {
            "\($0.itemTypeRawValue)|\($0.partID)|\($0.colorID)|\($0.quantity)"
        }.joined(separator: ",")
        return "\(order.persistentModelID)|\(orderToken)|\(sets.count)"
    }

    @MainActor
    private func loadMissingInSetsLookup() async {
        hasComputedMissingInSets = false

        let orderKeys = Set(order.parts.map { missingInSetsKey(for: $0) })
        guard !orderKeys.isEmpty else {
            missingInSetsLookup = [:]
            hasComputedMissingInSets = true
            return
        }

        let lookup = await buildMissingInSetsLookup(orderKeys: orderKeys)
        missingInSetsLookup = lookup
        hasComputedMissingInSets = true
    }

    @MainActor
    private func buildMissingInSetsLookup(orderKeys: Set<MissingInSetsKey>) async -> [MissingInSetsKey: Int] {
        var lookup: [MissingInSetsKey: Int] = [:]
        for set in sets {
            accumulateMissing(in: set, orderKeys: orderKeys, lookup: &lookup)
            await Task.yield()
        }
        return lookup
    }

    @MainActor
    private func accumulateMissing(
        in set: BrickSet,
        orderKeys: Set<MissingInSetsKey>,
        lookup: inout [MissingInSetsKey: Int]
    ) {
        for part in set.parts {
            accumulateMissing(part: part, orderKeys: orderKeys, lookup: &lookup)
        }
        for minifigure in set.minifigures {
            let key = MissingInSetsKey(
                itemType: .minifigure,
                partID: normalized(minifigure.identifier),
                colorID: ""
            )
            if orderKeys.contains(key) {
                let missing = max(minifigure.quantityNeeded - minifigure.quantityHave, 0)
                if missing > 0 {
                    lookup[key, default: 0] += missing
                }
            }
            for part in minifigure.parts {
                accumulateMissing(part: part, orderKeys: orderKeys, lookup: &lookup)
            }
        }
    }

    @MainActor
    private func accumulateMissing(
        part: Part,
        orderKeys: Set<MissingInSetsKey>,
        lookup: inout [MissingInSetsKey: Int]
    ) {
        guard part.inventorySection != .extra else { return }
        let missing = part.missingQuantity
        guard missing > 0 else { return }

        let key = MissingInSetsKey(
            itemType: .part,
            partID: normalized(part.partID),
            colorID: normalized(part.colorID)
        )
        guard orderKeys.contains(key) else { return }
        lookup[key, default: 0] += missing
    }

    private func missingInSetsKey(for orderPart: OrderPart) -> MissingInSetsKey {
        let normalizedPartID = normalized(orderPart.partID)
        if orderPart.itemType == .minifigure {
            return MissingInSetsKey(itemType: .minifigure, partID: normalizedPartID, colorID: "")
        }
        return MissingInSetsKey(
            itemType: orderPart.itemType,
            partID: normalizedPartID,
            colorID: normalized(orderPart.colorID)
        )
    }

    private func missingInSets(for part: OrderPart, lookup: [MissingInSetsKey: Int]) -> Int {
        let key = missingInSetsKey(for: part)
        return lookup[key] ?? 0
    }

    private func missingLookup(for set: BrickSet) -> MissingLookup {
        var partKeys = Set<MissingPartKey>()
        var minifigureIDs = Set<String>()

        func recordMissing(part: Part) {
            guard part.inventorySectionRawValue != Part.InventorySection.extra.rawValue else { return }
            guard hasMissingHierarchy(part) else { return }
            let key = MissingPartKey(
                partID: normalized(part.partID),
                colorID: normalized(part.colorID)
            )
            partKeys.insert(key)
        }

        for part in set.parts {
            recordMissing(part: part)
        }

        for minifigure in set.minifigures {
            if hasMissingHierarchy(minifigure) {
                minifigureIDs.insert(normalized(minifigure.identifier))
            }
            for part in minifigure.parts {
                recordMissing(part: part)
            }
        }

        return MissingLookup(partKeys: partKeys, minifigureIDs: minifigureIDs)
    }

    private var orderQuantityLookup: OrderQuantityLookup {
        var partQuantities: [MissingPartKey: Int] = [:]
        var minifigureQuantities: [String: Int] = [:]

        for part in order.parts {
            switch part.itemType {
            case .minifigure:
                let key = normalized(part.partID)
                minifigureQuantities[key, default: 0] += part.quantity
            case .part:
                let key = MissingPartKey(
                    partID: normalized(part.partID),
                    colorID: normalized(part.colorID)
                )
                partQuantities[key, default: 0] += part.quantity
            }
        }

        return OrderQuantityLookup(
            partQuantities: partQuantities,
            minifigureQuantities: minifigureQuantities
        )
    }

    private func orderQuantity(for part: Part, lookup: OrderQuantityLookup) -> Int {
        let key = MissingPartKey(
            partID: normalized(part.partID),
            colorID: normalized(part.colorID)
        )
        return lookup.partQuantities[key] ?? 0
    }

    private func orderQuantity(for minifigure: Minifigure, lookup: OrderQuantityLookup) -> Int {
        let key = normalized(minifigure.identifier)
        return lookup.minifigureQuantities[key] ?? 0
    }

    private func matchesSetFilter(_ part: OrderPart, lookup: MissingLookup) -> Bool {
        switch part.itemType {
        case .minifigure:
            return lookup.minifigureIDs.contains(normalized(part.partID))
        case .part:
            let key = MissingPartKey(
                partID: normalized(part.partID),
                colorID: normalized(part.colorID)
            )
            return lookup.partKeys.contains(key)
        }
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

    private func matchesOrderPart(_ part: OrderPart, query: String) -> Bool {
        let rawQuery = normalized(query)
        guard !rawQuery.isEmpty else { return false }

        let startsWithNumber = rawQuery.first?.isNumber == true
        let components = rawQuery.split(whereSeparator: { $0.isWhitespace })
        let primaryToken = components.first.map(String.init) ?? rawQuery
        let primaryTokenIsShortLength = isShortLengthToken(primaryToken)
        let primaryTokenIsNumericOnly = primaryToken.allSatisfy { $0.isNumber }
        let primaryTokenIsNumeric = primaryTokenIsNumericOnly && !primaryTokenIsShortLength
        let primaryTokenIsDimensionQuery = normalizedDimensionQuery(for: primaryToken) != nil
        let numericPrefixToken = String(primaryToken.prefix { $0.isNumber })
        let dimensionPrefixQuery = normalizedDimensionPrefix(in: rawQuery)
        let shouldEnforceNumericPrefix = !numericPrefixToken.isEmpty && dimensionPrefixQuery == nil && !primaryTokenIsShortLength
        let shouldMatchPartIDPrefix = startsWithNumber && !primaryTokenIsNumericOnly && !primaryTokenIsDimensionQuery && !primaryTokenIsShortLength
        let normalizedQueryTokens = queryTokens(from: rawQuery)
        let secondaryTokens = normalizedQueryTokens.dropFirst()

        let resolvedColor = resolvedColorName(for: part)
        let partIDLower = normalized(part.partID)
        let colorLower = normalized(resolvedColor)
        let nameLower = normalized(part.name)
        let searchable = searchableText(for: part, colorName: resolvedColor)
        let partTokens = partSearchTokens(for: part, colorName: resolvedColor)

        if shouldEnforceNumericPrefix, !matchesNumericPartID(part.partID, numericQuery: numericPrefixToken) {
            return false
        }

        if let dimensionPrefixQuery, !searchable.contains(dimensionPrefixQuery) {
            return false
        }

        let matches: Bool
        if dimensionPrefixQuery != nil {
            if normalizedQueryTokens.count <= 1 {
                matches = true
            } else {
                matches = secondaryTokens.allSatisfy { token in
                    matchesToken(token, partID: part.partID, partTokens: partTokens, searchableText: searchable)
                }
            }
        } else if primaryTokenIsNumeric {
            if secondaryTokens.isEmpty {
                matches = true
            } else {
                matches = secondaryTokens.allSatisfy { token in
                    matchesToken(token, partID: part.partID, partTokens: partTokens, searchableText: searchable)
                }
            }
        } else if primaryTokenIsDimensionQuery {
            matches = matchesToken(primaryToken, partID: part.partID, partTokens: partTokens, searchableText: searchable) &&
            secondaryTokens.allSatisfy { token in
                matchesToken(token, partID: part.partID, partTokens: partTokens, searchableText: searchable)
            }
        } else if shouldMatchPartIDPrefix {
            if !partIDLower.hasPrefix(primaryToken) {
                return false
            }
            if secondaryTokens.isEmpty {
                matches = true
            } else {
                matches = secondaryTokens.allSatisfy { token in
                    matchesToken(token, partID: part.partID, partTokens: partTokens, searchableText: searchable)
                }
            }
        } else if colorLower.contains(rawQuery) || nameLower.contains(rawQuery) {
            matches = true
        } else {
            matches = normalizedQueryTokens.allSatisfy { token in
                matchesToken(token, partID: part.partID, partTokens: partTokens, searchableText: searchable)
            }
        }

        return matches
    }

    private func matchesPartHierarchy(_ part: Part, query: String) -> Bool {
        if matchesPartSearch(part, query: query) {
            return true
        }

        return part.subparts.contains { matchesPartHierarchy($0, query: query) }
    }

    private func matchesMinifigureSearch(_ minifigure: Minifigure, query: String) -> Bool {
        let tokens = queryTokens(from: query)
        guard !tokens.isEmpty else { return true }

        let figureTokens = Set(queryTokens(from: "\(minifigure.identifier) \(minifigure.name)"))
        return tokens.allSatisfy { token in
            figureTokens.contains(where: { $0.contains(token) || $0.hasPrefix(token) })
        }
    }

    private func matchesPartSearch(_ part: Part, query: String) -> Bool {
        let rawQuery = normalized(query)
        guard !rawQuery.isEmpty else { return false }

        let startsWithNumber = rawQuery.first?.isNumber == true
        let components = rawQuery.split(whereSeparator: { $0.isWhitespace })
        let primaryToken = components.first.map(String.init) ?? rawQuery
        let primaryTokenIsShortLength = isShortLengthToken(primaryToken)
        let primaryTokenIsNumericOnly = primaryToken.allSatisfy { $0.isNumber }
        let primaryTokenIsNumeric = primaryTokenIsNumericOnly && !primaryTokenIsShortLength
        let primaryTokenIsDimensionQuery = normalizedDimensionQuery(for: primaryToken) != nil
        let numericPrefixToken = String(primaryToken.prefix { $0.isNumber })
        let dimensionPrefixQuery = normalizedDimensionPrefix(in: rawQuery)
        let shouldEnforceNumericPrefix = !numericPrefixToken.isEmpty && dimensionPrefixQuery == nil && !primaryTokenIsShortLength
        let shouldMatchPartIDPrefix = startsWithNumber && !primaryTokenIsNumericOnly && !primaryTokenIsDimensionQuery && !primaryTokenIsShortLength
        let normalizedQueryTokens = queryTokens(from: rawQuery)
        let secondaryTokens = normalizedQueryTokens.dropFirst()

        let colorName = part.colorName.isEmpty ? "Unknown Color" : part.colorName
        let partIDLower = normalized(part.partID)
        let colorLower = normalized(colorName)
        let nameLower = normalized(part.name)
        let searchable = searchableText(for: part, colorName: colorName)
        let partTokens = partSearchTokens(for: part, colorName: colorName)

        if shouldEnforceNumericPrefix, !matchesNumericPartID(part.partID, numericQuery: numericPrefixToken) {
            return false
        }

        if let dimensionPrefixQuery, !searchable.contains(dimensionPrefixQuery) {
            return false
        }

        let matches: Bool
        if dimensionPrefixQuery != nil {
            if normalizedQueryTokens.count <= 1 {
                matches = true
            } else {
                matches = secondaryTokens.allSatisfy { token in
                    matchesToken(token, partID: part.partID, partTokens: partTokens, searchableText: searchable)
                }
            }
        } else if primaryTokenIsNumeric {
            if secondaryTokens.isEmpty {
                matches = true
            } else {
                matches = secondaryTokens.allSatisfy { token in
                    matchesToken(token, partID: part.partID, partTokens: partTokens, searchableText: searchable)
                }
            }
        } else if primaryTokenIsDimensionQuery {
            matches = matchesToken(primaryToken, partID: part.partID, partTokens: partTokens, searchableText: searchable) &&
            secondaryTokens.allSatisfy { token in
                matchesToken(token, partID: part.partID, partTokens: partTokens, searchableText: searchable)
            }
        } else if shouldMatchPartIDPrefix {
            if !partIDLower.hasPrefix(primaryToken) {
                return false
            }
            if secondaryTokens.isEmpty {
                matches = true
            } else {
                matches = secondaryTokens.allSatisfy { token in
                    matchesToken(token, partID: part.partID, partTokens: partTokens, searchableText: searchable)
                }
            }
        } else if colorLower.contains(rawQuery) || nameLower.contains(rawQuery) {
            matches = true
        } else {
            matches = normalizedQueryTokens.allSatisfy { token in
                matchesToken(token, partID: part.partID, partTokens: partTokens, searchableText: searchable)
            }
        }

        return matches
    }

    private func partSearchTokens(for part: OrderPart, colorName: String) -> [String] {
        let combined = "\(part.partID) \(colorName) \(part.name)"
        return Array(Set(queryTokens(from: combined)))
    }

    private func partSearchTokens(for part: Part, colorName: String) -> [String] {
        let combined = "\(part.partID) \(colorName) \(part.name)"
        return Array(Set(queryTokens(from: combined)))
    }

    private func matchesToken(
        _ token: String,
        partID: String,
        partTokens: [String],
        searchableText: String
    ) -> Bool {
        if token.allSatisfy({ $0.isNumber }) && !isShortLengthToken(token) {
            if matchesNumericPartID(partID, numericQuery: token) {
                return true
            }

            return partTokens.contains { $0 == token }
        }

        if let dimensionQuery = normalizedDimensionQuery(for: token),
           searchableText.contains(dimensionQuery) {
            return true
        }

        return partTokens.contains { $0.hasPrefix(token) || $0.contains(token) }
    }

    private func isShortLengthToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        var normalizedToken = trimmed.lowercased()
        if normalizedToken.hasSuffix("l") {
            normalizedToken.removeLast()
        }

        guard (1...2).contains(normalizedToken.count) else { return false }
        return normalizedToken.allSatisfy { $0.isNumber }
    }

    private func matchesNumericPartID(_ partID: String, numericQuery: String) -> Bool {
        let normalizedQuery = normalized(numericQuery.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !normalizedQuery.isEmpty else { return false }

        let numericPrefix = normalized(partID.trimmingCharacters(in: .whitespacesAndNewlines))
            .prefix { $0.isNumber }

        guard !numericPrefix.isEmpty else { return false }
        return numericPrefix == normalizedQuery
    }

    private func normalizedDimensionPrefix(in query: String) -> String? {
        let prefix = query.prefix { character in
            character.isNumber || character.isWhitespace || character == "x" || character == "X" || character == "×"
        }
        guard !prefix.isEmpty else { return nil }
        return normalizedDimensionQuery(for: String(prefix))
    }

    private func normalizedDimensionQuery(for token: String) -> String? {
        let lowercased = normalized(token).replacingOccurrences(of: "×", with: "x")
        let compact = lowercased.replacingOccurrences(of: " ", with: "")

        guard compact.contains("x") else { return nil }

        let components = compact.split(separator: "x", omittingEmptySubsequences: false)
        guard components.count >= 2 else { return nil }

        let numericComponents = components.map(String.init)
        guard numericComponents.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isNumber } }) else {
            return nil
        }

        return numericComponents.joined(separator: " x ")
    }

    private func searchableText(for part: OrderPart, colorName: String) -> String {
        let combined = normalized("\(part.partID) \(colorName) \(part.name)")
            .replacingOccurrences(of: "×", with: "x")

        return combined
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func searchableText(for part: Part, colorName: String) -> String {
        let combined = normalized("\(part.partID) \(colorName) \(part.name)")
            .replacingOccurrences(of: "×", with: "x")

        return combined
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func queryTokens(from text: String) -> [String] {
        text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { normalized(String($0)) }
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private func hasMissingHierarchy(_ part: Part) -> Bool {
        if part.quantityHave < part.quantityNeeded {
            return true
        }

        return part.subparts.contains { hasMissingHierarchy($0) }
    }

    private func hasMissingHierarchy(_ minifigure: Minifigure) -> Bool {
        if minifigure.quantityHave < minifigure.quantityNeeded {
            return true
        }

        return minifigure.parts.contains { hasMissingHierarchy($0) }
    }

    private func updateSearchQuery() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            await MainActor.run { effectiveSearchText = "" }
            return
        }

        do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
        guard !Task.isCancelled else { return }
        await MainActor.run { effectiveSearchText = trimmed }
    }
}

private struct OrderPartRowView: View {
    let part: OrderPart
    let colorName: String
    let missingInSets: Int?

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

private struct OrderMinifigureRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var minifigure: Minifigure
    let orderQuantity: Int?

    init(minifigure: Minifigure, orderQuantity: Int? = nil) {
        self._minifigure = Bindable(minifigure)
        self.orderQuantity = orderQuantity
    }

    private var quantityBinding: Binding<Int> {
        Binding(
            get: { minifigure.quantityHave },
            set: { updateQuantity(to: $0) }
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            OrderMinifigureThumbnailView(url: minifigure.imageURL, size: 56)

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

                Stepper("", value: quantityBinding, in: 0...max(0, minifigure.quantityNeeded))
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

    private func updateQuantity(to newValue: Int) {
        let clamped = max(0, min(newValue, minifigure.quantityNeeded))
        guard clamped != minifigure.quantityHave else { return }

        let applyChange = {
            minifigure.quantityHave = clamped
            _minifigure.wrappedValue.synchronizeParts(to: clamped)
            try? modelContext.save()
        }

        withAnimation {
            applyChange()
        }
    }
}

private struct OrderMinifigureThumbnailView: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        Group {
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
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "person.fill")
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
