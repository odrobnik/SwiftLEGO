import SwiftUI
import SwiftData
#if canImport(BrickCore)
import BrickCore
#endif

private struct SetDetailShouldPropagateSearchFilterKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var setDetailShouldPropagateSearchFilter: Bool {
        get { self[SetDetailShouldPropagateSearchFilterKey.self] }
        set { self[SetDetailShouldPropagateSearchFilterKey.self] = newValue }
    }
}

struct SetDetailView: View {
    private static let segmentedSections: [Part.InventorySection] = [
        .regular,
        .counterpart,
        .alternate,
        .extra
    ]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.brickLinkService) private var brickLinkService
    @Environment(\.setDetailShouldPropagateSearchFilter) private var shouldPropagateSearchFilter
    let brickSet: BrickSet
    /// The section to open with; without one, the first section that has parts.
    private let initialSection: Part.InventorySection?
    @State private var selectedSection: Part.InventorySection
    @State private var searchText: String
    @State private var effectiveSearchText: String
    @State private var didApplyInitialState = false
    @State private var showMissingOnly: Bool = false
    @State private var isShowingLabelPrintSheet: Bool = false
    @State private var isRefreshingInventory: Bool = false
    @State private var refreshAlert: RefreshAlert?
    @State private var minifigureGroupExpansion = MinifigureGroupExpansion()

    /// Opens `brickSet` with the search field and section preset; both are only the
    /// starting values, which the user changes from there.
    init(
        brickSet: BrickSet,
        initialSearchText: String = "",
        initialSection: Part.InventorySection? = nil
    ) {
        self.brickSet = brickSet
        self.initialSection = initialSection
        self._selectedSection = State(initialValue: initialSection ?? .regular)
        self._searchText = State(initialValue: initialSearchText)
        self._effectiveSearchText = State(initialValue: initialSearchText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var normalizedSearchQuery: String? {
        let trimmed = effectiveSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    var body: some View {
        SetInventoryList(
            brickSet: brickSet,
            section: selectedSection,
            searchQuery: normalizedSearchQuery,
            showMissingOnly: showMissingOnly,
            minifigureGroupExpansion: minifigureGroupExpansion
        )
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search parts")
        .task(id: searchText) {
            await updateSearchQuery()
        }
        .onAppear {
            guard !didApplyInitialState else { return }
            didApplyInitialState = true
            if initialSection == nil {
                selectedSection = Self.firstSectionWithParts(in: brickSet)
            }
            if !shouldPropagateSearchFilter, !searchText.isEmpty {
                searchText = ""
            }
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
        .quickLookPresenter()
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

                Spacer()

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

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingLabelPrintSheet = true
                } label: {
                    Label("Print Label", systemImage: "printer")
                }
            }
        }
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

    private static func firstSectionWithParts(in brickSet: BrickSet) -> Part.InventorySection {
        for section in segmentedSections {
            if brickSet.parts.contains(where: { $0.inventorySection == section }) {
                return section
            }
        }

        return .regular
    }

    private func updateSearchQuery() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            effectiveSearchText = ""
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(200))
        } catch {
            return
        }

        guard !Task.isCancelled else { return }
        effectiveSearchText = trimmed
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
                refreshAlert = RefreshAlert(message: error.localizedDescription)
            }

            isRefreshingInventory = false
        }
    }
}

/// The parts of one inventory section of a set, grouped by colour, and its minifigures.
/// Filtering and grouping happen here, so they re-run when the debounced query or the
/// inventory changes rather than on every keystroke in the search field.
private struct SetInventoryList: View {
    let brickSet: BrickSet
    let section: Part.InventorySection
    /// The trimmed, lowercased search query, or `nil` when not searching.
    let searchQuery: String?
    let showMissingOnly: Bool
    /// Provided to the rows from here rather than from the set screen, whose body
    /// re-runs on every keystroke in the search field.
    let minifigureGroupExpansion: MinifigureGroupExpansion

    var body: some View {
        let query = searchQuery.map(InventoryQuery.init)
        let partGroups = partsByColor(matching: query)
        let minifigureGroups = visibleMinifigureGroups(matching: query)

        if partGroups.isEmpty && minifigureGroups.isEmpty {
            EmptyStateView(
                icon: "shippingbox",
                title: "No parts",
                message: searchQuery == nil ? "No parts to display." : "No parts match your search."
            )
        } else {
            List {
                ForEach(partGroups, id: \.color) { group in
                    Section(group.color) {
                        ForEach(group.parts) { part in
                            PartRowNavigationWrapper(part: part)
                        }
                    }
                }

                if !minifigureGroups.isEmpty {
                    Section("Minifigures") {
                        ForEach(minifigureGroups) { group in
                            MinifigureGroupRow(group: group)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.isFilteringMissingParts, showMissingOnly)
            .environment(minifigureGroupExpansion)
        }
    }

    private func partsByColor(matching query: InventoryQuery?) -> [(color: String, parts: [Part])] {
        let parts = brickSet.parts.filter { part in
            guard part.inventorySection == section else { return false }

            if showMissingOnly && !Self.hasMissingHierarchy(part) {
                return false
            }

            return query?.matchesHierarchy(of: part) ?? true
        }

        return Dictionary(grouping: parts) { part in
            Self.normalizedColorName(part.colorName)
        }
        .map { color, parts in
            let sortedParts = parts.sorted { lhs, rhs in
                Part.subpartSortComparator(lhs, rhs)
            }
            return (color: color, parts: sortedParts)
        }
        .sorted { lhs, rhs in lhs.color < rhs.color }
    }

    private func visibleMinifigureGroups(matching query: InventoryQuery?) -> [MinifigureGroup] {
        // Minifigures belong to the regular section, but a search shows them in every section.
        guard query != nil || section == .regular else { return [] }

        let minifigures = brickSet.minifigures.filter { minifigure in
            if showMissingOnly && !Self.hasMissingHierarchy(minifigure) {
                return false
            }

            guard let query else { return true }
            return query.matches(minifigure) || minifigure.parts.contains { query.matchesHierarchy(of: $0) }
        }

        let groups = Dictionary(grouping: minifigures) { $0.identifier.lowercased() }
            .values
            .compactMap(MinifigureGroup.init(instances:))
            .sorted { lhs, rhs in
                if lhs.name != rhs.name {
                    return lhs.name < rhs.name
                }
                return lhs.identifier < rhs.identifier
            }

        return showMissingOnly ? groups.filter(\.hasMissing) : groups
    }

    private static func normalizedColorName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown Color" : trimmed
    }

    private static func hasMissingHierarchy(_ part: Part) -> Bool {
        part.quantityHave < part.quantityNeeded || part.subparts.contains { hasMissingHierarchy($0) }
    }

    private static func hasMissingHierarchy(_ minifigure: Minifigure) -> Bool {
        minifigure.quantityHave < minifigure.quantityNeeded || minifigure.parts.contains { hasMissingHierarchy($0) }
    }
}

/// A search in the set screen, tokenized once for all the parts it is matched against.
private struct InventoryQuery {
    private struct Token {
        let text: String
        /// All digits and long enough to be a part number rather than a length like "4".
        let isPartNumber: Bool
        let dimension: String?
    }

    private let tokens: [Token]
    /// A leading number that part IDs have to start with, unless the query is a
    /// dimension like "2 x 4".
    private let requiredPartNumberPrefix: String?

    init(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = Self.words(in: query)

        tokens = words.map { word in
            Token(
                text: word,
                isPartNumber: word.allSatisfy(\.isNumber) && !Self.isShortLengthToken(word),
                dimension: Self.normalizedDimensionQuery(for: word)
            )
        }

        let primaryTokenIsShortLength = words.first.map(Self.isShortLengthToken) ?? false
        let numericPrefix = String(trimmedQuery.prefix(while: \.isNumber))

        if !numericPrefix.isEmpty && !primaryTokenIsShortLength {
            let remainder = trimmedQuery.dropFirst(numericPrefix.count).drop(while: \.isWhitespace)
            let isDimensionQuery = remainder.first.map { ["x", "X", "×"].contains($0) } ?? false
            requiredPartNumberPrefix = isDimensionQuery ? nil : numericPrefix
        } else {
            requiredPartNumberPrefix = nil
        }
    }

    func matchesHierarchy(of part: Part) -> Bool {
        matches(part) || part.subparts.contains { matchesHierarchy(of: $0) }
    }

    func matches(_ part: Part) -> Bool {
        if let requiredPartNumberPrefix,
           !matchesNumericPartID(part.partID, numericQuery: requiredPartNumberPrefix) {
            return false
        }

        guard !tokens.isEmpty else { return true }

        let partWords = Set(Self.words(in: "\(part.partID) \(part.colorName) \(part.name)"))
        let lowercasedPartName = part.name.lowercased()

        return tokens.allSatisfy { token in
            if token.isPartNumber {
                return matchesNumericPartID(part.partID, numericQuery: token.text) || partWords.contains(token.text)
            }

            if let dimension = token.dimension, lowercasedPartName.contains(dimension) {
                return true
            }

            return partWords.contains { $0.contains(token.text) }
        }
    }

    func matches(_ minifigure: Minifigure) -> Bool {
        guard !tokens.isEmpty else { return true }

        let figureWords = Set(Self.words(in: "\(minifigure.identifier) \(minifigure.name)"))

        return tokens.allSatisfy { token in
            figureWords.contains { $0.contains(token.text) }
        }
    }

    private static func words(in text: String) -> [String] {
        text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { $0.lowercased() }
    }

    private static func isShortLengthToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        var normalizedToken = trimmed.lowercased()
        if normalizedToken.hasSuffix("l") {
            normalizedToken.removeLast()
        }

        guard (1...2).contains(normalizedToken.count) else { return false }
        return normalizedToken.allSatisfy(\.isNumber)
    }

    private static func normalizedDimensionQuery(for token: String) -> String? {
        let compact = token
            .lowercased()
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: " ", with: "")

        guard compact.contains("x") else { return nil }

        let components = compact.split(separator: "x", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 2,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }

        return components.joined(separator: " x ")
    }
}

private func matchesNumericPartID(_ partID: String, numericQuery: String) -> Bool {
    let normalizedQuery = numericQuery
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    guard !normalizedQuery.isEmpty else { return false }

    let numericPrefix = partID
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .prefix(while: \.isNumber)

    guard !numericPrefix.isEmpty else { return false }
    return numericPrefix == normalizedQuery
}

private struct RefreshAlert: Identifiable {
    let id = UUID()
    let message: String
}

/// The copies of one minifigure in a set.
private struct MinifigureGroup: Identifiable {
    let identifier: String
    let name: String
    let instances: [Minifigure]

    /// Groups `instances`, ordered by instance number; `nil` when there are none.
    init?(instances: [Minifigure]) {
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
        self.identifier = representative.identifier
        self.name = representative.name
        self.instances = sortedInstances
    }

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

/// Which multi-copy minifigure groups the user expanded or collapsed. The set screen
/// owns it, so the choice survives rows being recreated while scrolling or filtering.
@MainActor
@Observable
private final class MinifigureGroupExpansion {
    private var isExpandedByGroupID: [String: Bool] = [:]

    func isExpanded(_ group: MinifigureGroup, default defaultValue: Bool) -> Bool {
        isExpandedByGroupID[group.id] ?? defaultValue
    }

    func setExpanded(_ isExpanded: Bool, for group: MinifigureGroup) {
        isExpandedByGroupID[group.id] = isExpanded
    }
}

/// A minifigure of the set: one row for a single copy, or a disclosure group with a
/// combined stepper for several copies.
private struct MinifigureGroupRow: View {
    @Environment(\.isFilteringMissingParts) private var isFilteringMissing
    @Environment(MinifigureGroupExpansion.self) private var expansion
    let group: MinifigureGroup

    var body: some View {
        if group.instanceCount <= 1, let instance = group.instances.first {
            NavigationLink(value: instance) {
                MinifigureInstanceRowView(minifigure: instance, includeInstanceSuffix: false)
            }
            .buttonStyle(.plain)
        } else {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(group.instances) { minifigure in
                    NavigationLink(value: minifigure) {
                        MinifigureInstanceRowView(minifigure: minifigure, includeInstanceSuffix: true)
                            .padding(.leading, 12)
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
                .padding(.top, 6)
            } label: {
                MinifigureGroupSummaryView(group: group)
            }
            .padding(.vertical, 6)
        }
    }

    /// Collapsed until the user expands it, except while missing parts are filtered and
    /// a copy is still incomplete.
    private var isExpanded: Binding<Bool> {
        Binding(
            get: { expansion.isExpanded(group, default: isFilteringMissing && group.hasMissing) },
            set: { expansion.setExpanded($0, for: group) }
        )
    }
}

private struct MinifigureGroupSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    let group: MinifigureGroup

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
                    Text("Includes ^[\(group.instanceCount) copy](inflect: true)")
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

                Stepper("", value: totalHave, in: 0...max(group.totalNeeded, 0))
                    .labelsHidden()
            }
            .frame(minWidth: 90, idealWidth: 110)
        }
        .padding(.vertical, 6)
    }

    private var totalHave: Binding<Int> {
        Binding(
            get: { group.totalHave },
            set: { updateTotal(to: $0) }
        )
    }

    /// Spreads a new total over the copies: additions fill the first copies first,
    /// removals empty the last copies first.
    private func updateTotal(to newValue: Int) {
        let clamped = max(0, min(newValue, group.totalNeeded))
        let current = group.totalHave
        guard clamped != current else { return }

        withAnimation {
            if clamped > current {
                var remaining = clamped - current
                for figure in group.instances {
                    guard remaining > 0 else { break }
                    let capacity = figure.quantityNeeded - figure.quantityHave
                    guard capacity > 0 else { continue }
                    let addition = min(capacity, remaining)
                    figure.quantityHave += addition
                    figure.synchronizeParts(to: figure.quantityHave)
                    remaining -= addition
                }
            } else {
                var remaining = current - clamped
                for figure in group.instances.reversed() {
                    guard remaining > 0 else { break }
                    let reduction = min(figure.quantityHave, remaining)
                    guard reduction > 0 else { continue }
                    figure.quantityHave -= reduction
                    figure.synchronizeParts(to: figure.quantityHave)
                    remaining -= reduction
                }
            }
            try? modelContext.save()
        }
    }
}

private struct MinifigureInstanceRowView: View {
    @Environment(\.modelContext) private var modelContext
    let minifigure: Minifigure
    let includeInstanceSuffix: Bool

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

                Stepper("", value: quantityHave, in: 0...max(0, minifigure.quantityNeeded))
                    .labelsHidden()
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

struct PartRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.isFilteringMissingParts) private var isFilteringMissing
    let part: Part
    var orderQuantity: Int? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            PartRowThumbnail(part: part)

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

                Stepper("", value: quantityHave, in: 0...part.quantityNeeded)
                    .labelsHidden()

                if let orderQuantity, orderQuantity > 0 {
                    Text("^[\(orderQuantity) part](inflect: true) in order")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 80, idealWidth: 100)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                markComplete()
            } label: {
                Label("Have All", systemImage: "checkmark.circle.fill")
            }
            .tint(.green)
            .disabled(part.quantityHave >= part.quantityNeeded)
        }
    }

    private var quantityHave: Binding<Int> {
        Binding(
            get: { part.quantityHave },
            set: { updateQuantity(to: $0) }
        )
    }

    private func markComplete() {
        if isFilteringMissing && part.quantityHave < part.quantityNeeded {
            withAnimation(.easeInOut) {
                setQuantity(part.quantityNeeded)
            }
        } else {
            setQuantity(part.quantityNeeded)
        }
    }

    private func updateQuantity(to newValue: Int) {
        let clampedValue = max(0, min(newValue, part.quantityNeeded))
        let oldValue = part.quantityHave
        guard clampedValue != oldValue else { return }

        // While missing parts are filtered, completing a part removes its row.
        if isFilteringMissing && oldValue < part.quantityNeeded && clampedValue == part.quantityNeeded {
            withAnimation {
                setQuantity(clampedValue)
            }
        } else {
            setQuantity(clampedValue)
        }
    }

    private func setQuantity(_ value: Int) {
        part.quantityHave = value
        part.synchronizeSubparts(to: value)
        part.propagateCompletionUpwardsIfNeeded()
        try? modelContext.save()
    }
}

private struct PartRowThumbnail: View {
    let part: Part

    var body: some View {
        QuickLookThumbnail(item: part) {
            if let url = part.thumbnailImageURL {
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
                            ThumbnailPlaceholder(systemImage: "cube.transparent", scalesSymbol: true, width: 64, height: 64)
                            Button("Retry") {
                                state.retry()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .background(.white)
            } else {
                ThumbnailPlaceholder(systemImage: "cube.transparent", scalesSymbol: true, width: 64, height: 64)
            }
        }
    }
}

/// A part row that opens the part's sub-parts when it has any.
struct PartRowNavigationWrapper: View {
    let part: Part
    var orderQuantity: Int? = nil

    var body: some View {
        if part.subparts.isEmpty {
            PartRowView(part: part, orderQuantity: orderQuantity)
        } else {
            NavigationLink {
                PartDetailView(part: part)
            } label: {
                PartRowView(part: part, orderQuantity: orderQuantity)
            }
        }
    }
}

#Preview("Set Detail") {
    let container = SwiftLEGOModelContainer.preview
    let context = ModelContext(container)
    let set = try! context.fetch(FetchDescriptor<BrickSet>()).first!

    return NavigationStack {
        SetDetailView(brickSet: set, initialSearchText: "bla", initialSection: .regular)
    }
    .modelContainer(container)
}
