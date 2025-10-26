import SwiftUI
import SwiftData
#if canImport(BrickCore)
import BrickCore
#endif

struct SetDetailView: View {
    private static let segmentedSections: [Part.InventorySection] = [
        .regular,
        .counterpart,
        .alternate,
        .extra
    ]

    @Environment(\.modelContext) private var modelContext
    private let brickLinkService = BrickLinkService()
    @Bindable var brickSet: BrickSet
    @State private var selectedSection: Part.InventorySection
    @State private var searchText: String
    @State private var showMissingOnly: Bool = false
    @State private var isShowingLabelPrintSheet: Bool = false
    @State private var isRefreshingInventory: Bool = false
    @State private var refreshAlert: RefreshAlert?
    @State private var minifigureGroupExpansion: [String: Bool] = [:]

    init(brickSet: BrickSet, searchText: String = "") {
        self._brickSet = Bindable(brickSet)
        self._selectedSection = State(initialValue: Self.initialSection(for: brickSet))
        self._searchText = State(initialValue: searchText)
    }

    private var minifigureGroups: [MinifigureGroup] {
        if normalizedSearchQuery == nil && !shouldShowMinifigures {
            return []
        }

        let grouped = Dictionary(grouping: filteredMinifigures) { $0.identifier.lowercased() }

        let mapped = grouped.values.compactMap { instances -> MinifigureGroup? in
            guard !instances.isEmpty else { return nil }
            let sortedInstances = instances.sorted { lhs, rhs in
                if lhs.instanceNumber != rhs.instanceNumber {
                    return lhs.instanceNumber < rhs.instanceNumber
                }
                if lhs.name != rhs.name {
                    return lhs.name < rhs.name
                }
                return lhs.identifier < rhs.identifier
            }

            guard let representative = sortedInstances.first else { return nil }
            return MinifigureGroup(
                identifier: representative.identifier,
                name: representative.name,
                instances: sortedInstances
            )
        }

        return mapped.sorted { lhs, rhs in
            if lhs.name != rhs.name {
                return lhs.name < rhs.name
            }
            return lhs.identifier < rhs.identifier
        }
    }

    private var partsByColor: [(color: String, parts: [Part])] {
        let grouped = Dictionary(grouping: filteredParts) { part in
            normalizeColorName(part.colorName)
        }

        return grouped
            .map { (color: $0.key, parts: $0.value.sorted(by: colorPartSortComparator)) }
            .sorted { lhs, rhs in lhs.color < rhs.color }
    }

    private var filteredParts: [Part] {
        brickSet.parts.filter { part in
            guard part.inventorySection == selectedSection else { return false }

            if showMissingOnly && !hasMissingHierarchy(part) {
                return false
            }

            guard let searchQuery = normalizedSearchQuery else {
                return true
            }

            return matchesHierarchy(part, query: searchQuery)
        }
    }

    private var filteredMinifigures: [Minifigure] {
        let minifiguresMatchingMissingToggle = brickSet.minifigures.filter { minifigure in
            !showMissingOnly || hasMissingHierarchy(minifigure: minifigure)
        }

        guard let query = normalizedSearchQuery else {
            return minifiguresMatchingMissingToggle
        }

        return minifiguresMatchingMissingToggle.filter { minifigure in
            matchesMinifigure(minifigure, query: query) ||
            minifigure.parts.contains { matchesHierarchy($0, query: query) }
        }
    }

    private var normalizedSearchQuery: String? {
        let trimmed = searchText
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    var body: some View {
        
        Group {
            if partsByColor.isEmpty && minifigureGroups.isEmpty {
                
                EmptyStateView(icon: "shippingbox", title: "No parts", message: normalizedSearchQuery == nil ? "No parts to display." : "No parts match your search.")
            } else {
                
                
                
                List {
                    // headerSection
                    
                    
                    
                    if !partsByColor.isEmpty {
                        ForEach(partsByColor, id: \.color) { group in
                            Section(group.color) {
                                ForEach(group.parts) { part in
                                    PartRowNavigationWrapper(
                                        part: part,
                                        isFilteringMissing: showMissingOnly
                                    )
                                }
                            }
                        }
                    }
                    
                    if !minifigureGroups.isEmpty {
                        minifigureSection
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search parts")
        .task(id: searchText) {
            await updateSearchQuery()
        }
        .sheet(isPresented: $isShowingLabelPrintSheet) {
            LabelPrintSheet(brickSet: brickSet)
        }
        .alert(item: $refreshAlert) { alert in
            Alert(
                title: Text("Refresh Failed"),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .toolbarTitleDisplayMode(.inline)
        .navigationTitle("\(brickSet.setNumber) \(brickSet.name)")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isRefreshingInventory {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Refreshing inventory")
                } else {
                    Button {
                        refreshInventory()
                    } label: {
                        Label("Refresh from BrickLink", systemImage: "arrow.clockwise")
                    }
                    .help("Re-fetch parts and minifigures from BrickLink")
                }
            }
            
            ToolbarItemGroup(placement: .bottomBar) {
                Picker("Inventory Section", selection: $selectedSection) {
                    ForEach(Self.segmentedSections, id: \.self) { section in
                        Text(segmentedTitle(for: section)).tag(section)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingLabelPrintSheet = true
                } label: {
                    Label("Print Label", systemImage: "printer")
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation {
                        showMissingOnly.toggle()
                    }
                } label: {
                    Image(systemName: showMissingOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(showMissingOnly ? Color.accentColor : Color.secondary)
                        .imageScale(.large)
                        .accessibilityLabel(showMissingOnly ? "Showing missing parts" : "Show only missing parts")
                }
                .buttonStyle(.plain)
                .help("Toggle missing parts filter")
            }
        }
    }

    private var minifigureSection: some View {
        Section("Minifigures") {
            ForEach(minifigureGroups) { group in
                if group.instanceCount <= 1, let instance = group.instances.first {
                    NavigationLink(value: instance) {
                        MinifigureInstanceRowView(
                            minifigure: instance,
                            includeInstanceSuffix: false
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    DisclosureGroup(
                        isExpanded: expansionBinding(for: group)
                    ) {
                        ForEach(group.instances) { minifigure in
                            NavigationLink(value: minifigure) {
                                MinifigureInstanceRowView(
                                    minifigure: minifigure,
                                    includeInstanceSuffix: true
                                )
                                .padding(.leading, 12)
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                        }
                        .padding(.top, 6)
                    } label: {
                        MinifigureGroupSummaryView(
                            group: group,
                            quantityBinding: aggregateQuantityBinding(for: group)
                        )
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var headerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 16) {
                HeaderThumbnail(brickSet: brickSet)

                VStack(alignment: .leading, spacing: 8) {
                    Text(brickSet.setNumber)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(brickSet.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)

                    let categories = brickSet.normalizedCategoryPath(uncategorizedTitle: "Uncategorized")
                    if !categories.isEmpty {
                        Text(categories.joined(separator: " / "))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    private func normalizeColorName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown Color" : trimmed
    }

    private func colorPartSortComparator(_ lhs: Part, _ rhs: Part) -> Bool {
        if lhs.name != rhs.name {
            return lhs.name < rhs.name
        }

        return lhs.partID < rhs.partID
    }

    private func segmentedTitle(for section: Part.InventorySection) -> String {
        switch section {
        case .regular:
            return "Regular"
        case .counterpart:
            return "Counterpart"
        case .alternate:
            return "Alternate"
        case .extra:
            return "Extras"
        }
    }

    private func aggregateQuantityBinding(for group: MinifigureGroup) -> Binding<Int> {
        Binding(
            get: { group.totalHave },
            set: { updateQuantity(for: group, to: $0) }
        )
    }

    private func updateQuantity(for group: MinifigureGroup, to newValue: Int) {
        let totalNeeded = group.totalNeeded
        let clamped = max(0, min(newValue, totalNeeded))
        let current = group.totalHave
        guard clamped != current else { return }

        if clamped > current {
            var remaining = clamped - current
            withAnimation {
                for figure in group.instances {
                    guard remaining > 0 else { break }
                    let capacity = figure.quantityNeeded - figure.quantityHave
                    guard capacity > 0 else { continue }
                    let addition = min(capacity, remaining)
                    figure.quantityHave += addition
                    figure.synchronizeParts(to: figure.quantityHave)
                    remaining -= addition
                }
                try? modelContext.save()
            }
        } else {
            var remaining = current - clamped
            withAnimation {
                for figure in group.instances.reversed() {
                    guard remaining > 0 else { break }
                    let reduction = min(figure.quantityHave, remaining)
                    guard reduction > 0 else { continue }
                    figure.quantityHave -= reduction
                    figure.synchronizeParts(to: figure.quantityHave)
                    remaining -= reduction
                }
                try? modelContext.save()
            }
        }
    }

    private func expansionBinding(for group: MinifigureGroup) -> Binding<Bool> {
        Binding(
            get: { minifigureGroupExpansion[group.id] ?? defaultExpansion(for: group) },
            set: { minifigureGroupExpansion[group.id] = $0 }
        )
    }

    private func defaultExpansion(for group: MinifigureGroup) -> Bool {
        group.instanceCount <= 1 || (showMissingOnly && group.hasMissing)
    }

    private var shouldShowMinifigures: Bool {
        selectedSection == .regular
    }

    private static func initialSection(for brickSet: BrickSet) -> Part.InventorySection {
        for section in segmentedSections {
            if brickSet.parts.contains(where: { $0.inventorySection == section }) {
                return section
            }
        }

        return .regular
    }

    private func matchesHierarchy(_ part: Part, query: String) -> Bool {
        if matchesSearch(part, query: query) {
            return true
        }

        return part.subparts.contains { matchesHierarchy($0, query: query) }
    }

    private func hasMissingHierarchy(_ part: Part) -> Bool {
        if part.quantityHave < part.quantityNeeded {
            return true
        }

        return part.subparts.contains { hasMissingHierarchy($0) }
    }

    private func hasMissingHierarchy(minifigure: Minifigure) -> Bool {
        if minifigure.quantityHave < minifigure.quantityNeeded {
            return true
        }

        return minifigure.parts.contains { hasMissingHierarchy($0) }
    }

    private func matchesSearch(_ part: Part, query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let numericPrefixToken = String(trimmedQuery.prefix { $0.isNumber })
        if !numericPrefixToken.isEmpty {
            let remainder = trimmedQuery.dropFirst(numericPrefixToken.count)
            let remainderAfterSpaces = remainder.drop(while: { $0.isWhitespace })
            let isDimensionQuery = remainderAfterSpaces.first.map { ["x", "X", "×"].contains($0) } ?? false

            if !isDimensionQuery {
                guard matchesNumericPartID(part.partID, numericQuery: numericPrefixToken) else { return false }
            }
        }

        let queryTokens = wordPrefixes(in: query)
        guard !queryTokens.isEmpty else { return true }

        let partTokens = Set(wordPrefixes(in: "\(part.partID) \(part.colorName) \(part.name)"))
        let lowercasedPartName = part.name.lowercased()

        return queryTokens.allSatisfy { token in
            if token.allSatisfy({ $0.isNumber }) {
                if matchesNumericPartID(part.partID, numericQuery: token) {
                    return true
                }

                return partTokens.contains(token)
            }

            if let dimensionQuery = normalizedDimensionQuery(for: token),
               lowercasedPartName.contains(dimensionQuery) {
                return true
            }

            return partTokens.contains(where: { $0.contains(token) || $0.hasPrefix(token) })
        }
    }

    private func matchesMinifigure(_ minifigure: Minifigure, query: String) -> Bool {
        let queryTokens = wordPrefixes(in: query)
        guard !queryTokens.isEmpty else { return true }

        let figureTokens = Set(wordPrefixes(in: "\(minifigure.identifier) \(minifigure.name)"))

        return queryTokens.allSatisfy { token in
            figureTokens.contains(where: { $0.contains(token) || $0.hasPrefix(token) })
        }
    }

    private func wordPrefixes(in text: String) -> [String] {
        text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { $0.lowercased() }
    }

    private func normalizedDimensionQuery(for token: String) -> String? {
        let lowercased = token
            .lowercased()
            .replacingOccurrences(of: "×", with: "x")
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

    private func updateSearchQuery() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            await MainActor.run { searchText = "" }
            return
        }

        do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
        guard !Task.isCancelled else { return }
        await MainActor.run { searchText = trimmed }
    }

    private func refreshInventory() {
        guard !isRefreshingInventory else { return }
        isRefreshingInventory = true

        Task {
            do {
                try await SetImportUtilities.refreshSetFromBrickLink(
                    set: brickSet,
                    modelContext: modelContext,
                    service: brickLinkService
                )
            } catch {
                await MainActor.run {
                    refreshAlert = RefreshAlert(message: refreshErrorMessage(for: error))
                }
            }

            await MainActor.run {
                isRefreshingInventory = false
            }
        }
    }

    private func refreshErrorMessage(for error: Error) -> String {
        if let refreshError = error as? SetImportUtilities.RefreshError {
            return refreshError.localizedDescription
        }

        return error.localizedDescription
    }

}

private func matchesNumericPartID(_ partID: String, numericQuery: String) -> Bool {
    guard !numericQuery.isEmpty else { return false }
    let numericPrefix = partID.prefix { $0.isNumber }
    guard !numericPrefix.isEmpty else { return false }
    return String(numericPrefix).caseInsensitiveCompare(numericQuery) == .orderedSame
}

private struct RefreshAlert: Identifiable {
    let id = UUID()
    let message: String
}

private struct HeaderThumbnail: View {
    let brickSet: BrickSet

    var body: some View {
        thumbnail
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = brickSet.thumbnailURL {
            ThumbnailImage(url: url) { phase in
                switch phase {
                case .empty, .loading:
                    ProgressView()
                        .frame(width: 44, height: 44)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                case .failure(let state):
                    VStack(spacing: 8) {
                        placeholder
                        Button("Retry") {
                            state.retry()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemFill))
            .frame(width: 96, height: 96)
            .overlay {
                Image(systemName: "cube.transparent")
                    .foregroundStyle(.secondary)
            }
    }
}

private struct MinifigureGroup: Identifiable {
    let identifier: String
    let name: String
    let instances: [Minifigure]

    var id: String {
        let suffix = instances.map { "\($0.instanceNumber)" }.joined(separator: "-")
        return "\(identifier.lowercased())|\(suffix)"
    }

    var totalNeeded: Int {
        instances.reduce(0) { $0 + $1.quantityNeeded }
    }

    var totalHave: Int {
        instances.reduce(0) { $0 + $1.quantityHave }
    }

    var imageURL: URL? {
        instances.first?.imageURL
    }

    var instanceCount: Int {
        instances.count
    }

    var hasMissing: Bool {
        totalHave < totalNeeded
    }
}

private struct MinifigureGroupRow: View {
    @Environment(\.modelContext) private var modelContext
    let group: MinifigureGroup
    let isFilteringMissing: Bool
    @State private var isExpanded: Bool

    init(group: MinifigureGroup, isFilteringMissing: Bool) {
        self.group = group
        self.isFilteringMissing = isFilteringMissing
        let shouldExpand = group.instanceCount <= 1 || (isFilteringMissing && group.hasMissing)
        self._isExpanded = State(initialValue: shouldExpand)
    }

    var body: some View {
        if group.instanceCount <= 1, let instance = group.instances.first {
            NavigationLink(value: instance) {
                MinifigureInstanceRowView(
                    minifigure: instance,
                    includeInstanceSuffix: false
                )
            }
            .buttonStyle(.plain)
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(spacing: 0) {
                    ForEach(group.instances) { minifigure in
                        NavigationLink(value: minifigure) {
                            MinifigureInstanceRowView(
                                minifigure: minifigure,
                                includeInstanceSuffix: true
                            )
                            .padding(.leading, 12)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.top, 6)
            } label: {
                MinifigureGroupSummaryView(
                    group: group,
                    quantityBinding: aggregateQuantityBinding
                )
            }
            .padding(.vertical, 6)
        }
    }

    private var aggregateQuantityBinding: Binding<Int> {
        Binding(
            get: { group.totalHave },
            set: { updateGroupQuantity(to: $0) }
        )
    }

    private func updateGroupQuantity(to newValue: Int) {
        let totalNeeded = group.totalNeeded
        let clamped = max(0, min(newValue, totalNeeded))
        let current = group.totalHave
        guard clamped != current else { return }

        if clamped > current {
            var remaining = clamped - current
            withAnimation {
                for figure in group.instances {
                    guard remaining > 0 else { break }
                    let capacity = figure.quantityNeeded - figure.quantityHave
                    guard capacity > 0 else { continue }
                    let addition = min(capacity, remaining)
                    figure.quantityHave += addition
                    remaining -= addition
                }
                try? modelContext.save()
            }
        } else {
            var remaining = current - clamped
            withAnimation {
                for figure in group.instances.reversed() {
                    guard remaining > 0 else { break }
                    let reduction = min(figure.quantityHave, remaining)
                    guard reduction > 0 else { continue }
                    figure.quantityHave -= reduction
                    remaining -= reduction
                }
                try? modelContext.save()
            }
        }
    }

}

private struct MinifigureGroupSummaryView: View {
    let group: MinifigureGroup
    let quantityBinding: Binding<Int>

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            MinifigureThumbnailView(url: group.imageURL, size: 64)

            VStack(alignment: .leading, spacing: 6) {
                Text(group.name)
                    .font(.headline)

                Text(group.identifier)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if group.instanceCount > 1 {
                    Text("Includes \(group.instanceCount) copies")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .center, spacing: 4) {
                Text("\(group.totalHave) of \(group.totalNeeded)")
                    .font(.title3.bold())
                    .contentTransition(.numericText())
                    .lineLimit(1)

                Stepper("", value: quantityBinding, in: 0...max(group.totalNeeded, 0))
                    .labelsHidden()
            }
            .frame(minWidth: 90, idealWidth: 110)
        }
        .padding(.vertical, 6)
    }
}

private struct MinifigureInstanceRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var minifigure: Minifigure
    let includeInstanceSuffix: Bool

    private var quantityBinding: Binding<Int> {
        Binding(
            get: { minifigure.quantityHave },
            set: { updateQuantity(to: $0) }
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            MinifigureThumbnailView(url: minifigure.imageURL, size: 56)

            VStack(alignment: .leading, spacing: 6) {
                Text(minifigure.name)
                    .font(.headline)

                Text(minifigure.displayIdentifier(includeInstanceSuffix: includeInstanceSuffix))
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

private struct MinifigureThumbnailView: View {
    let url: URL?
    let size: CGFloat

    init(url: URL?, size: CGFloat = 64) {
        self.url = url
        self.size = size
    }

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

struct PartRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var part: Part
    let isFilteringMissing: Bool

    private var quantityBinding: Binding<Int> {
        Binding(
            get: { part.quantityHave },
            set: { newValue in
                updateQuantity(to: newValue)
            }
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                Text(part.name)
                    .font(.headline)

                Text("\(part.partID) • \(part.colorName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .center, spacing: 4) {
                Text("\(part.quantityHave) of \(part.quantityNeeded)")
                    .font(.title3.bold())
                    .contentTransition(.numericText())

                Stepper("", value: quantityBinding, in: 0...part.quantityNeeded)
                    .labelsHidden()
            }
            .frame(minWidth: 80, idealWidth: 100)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                let shouldAnimate = isFilteringMissing && part.quantityHave < part.quantityNeeded
                let update = {
                    part.quantityHave = part.quantityNeeded
                    let model = _part.wrappedValue
                    model.synchronizeSubparts(to: part.quantityNeeded)
                    model.propagateCompletionUpwardsIfNeeded()
                    try? modelContext.save()
                }

                if shouldAnimate {
                    withAnimation(.easeInOut) {
                        update()
                    }
                } else {
                    update()
                }
            } label: {
                Label("Have All", systemImage: "checkmark.circle.fill")
            }
            .tint(.green)
            .disabled(part.quantityHave >= part.quantityNeeded)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = part.imageURL {
            ThumbnailImage(url: url) { phase in
                switch phase {
                case .empty, .loading:
                    ProgressView()
                        .frame(width: 80, height: 60)
                case .success(let image):
                    image
//                        .resizable()
//                        .scaledToFit()
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

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemFill))
            .frame(width: 64, height: 64)
            .overlay {
                Image(systemName: "cube.transparent")
                    .foregroundStyle(.secondary)
            }
    }

    private func updateQuantity(to newValue: Int) {
        let clampedValue = max(0, min(newValue, part.quantityNeeded))
        let oldValue = part.quantityHave
        guard clampedValue != oldValue else { return }

        let update = {
            part.quantityHave = clampedValue
            let model = _part.wrappedValue
            model.synchronizeSubparts(to: clampedValue)
            model.propagateCompletionUpwardsIfNeeded()
            try? modelContext.save()
        }

        withAnimation {
            update()
        }
    }
}

struct PartRowNavigationWrapper: View {
    @Bindable var part: Part
    let isFilteringMissing: Bool

    var body: some View {
        if part.subparts.isEmpty {
            PartRowView(part: part, isFilteringMissing: isFilteringMissing)
        } else {
            NavigationLink {
                PartDetailView(part: part)
            } label: {
                PartRowView(part: part, isFilteringMissing: isFilteringMissing)
            }
        }
    }
}

#Preview("Set Detail") {
    let container = SwiftLEGOModelContainer.preview
    let context = ModelContext(container)
    let set = try! context.fetch(FetchDescriptor<BrickSet>()).first!

    return NavigationStack {
        SetDetailView(brickSet: set, searchText: "bla")
    }
    .modelContainer(container)
}
