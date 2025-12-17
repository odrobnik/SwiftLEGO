import SwiftUI
import SwiftData
import BrickCore

struct OrderDetailView: View {
    @Query private var colors: [BrickColor]
    @Bindable var order: BrickOrder
    @State private var searchText: String = ""
    @State private var effectiveSearchText: String = ""

    private var filteredParts: [OrderPart] {
        guard let query = normalizedSearchQuery else {
            return order.parts
        }
        return order.parts.filter { part in
            matchesOrderPart(part, query: query)
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
        let trimmed = effectiveSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var forwardedSearchQuery: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
                                NavigationLink(value: OrderPartRoute(orderPart: part, searchQuery: forwardedSearchQuery)) {
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
        .task(id: searchText) {
            await updateSearchQuery()
        }
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

    private func partSearchTokens(for part: OrderPart, colorName: String) -> [String] {
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

    private func queryTokens(from text: String) -> [String] {
        text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { normalized(String($0)) }
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
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
