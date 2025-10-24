import SwiftUI
import SwiftData

struct SetCollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var list: CollectionList
    private let brickLinkService = BrickLinkService()
    @State private var showingAddSetSheet = false
    @State private var showingBulkAddSheet = false
    @State private var setBeingRenamed: BrickSet?
    @State private var searchText: String = ""
    @State private var searchScope: SearchScope = .sets
    @State private var effectiveSearchText: String = ""
    @State private var labelPrintTarget: BrickSet?
    @State private var partSearchResults: [PartSearchEntry] = []
    @State private var minifigureSearchResults: [MinifigureSearchEntry] = []
    @State private var refreshingSetIDs: Set<PersistentIdentifier> = []
    @State private var refreshError: RefreshError?

    init(list: CollectionList) {
        self._list = Bindable(list)
    }

    private var sortedSets: [BrickSet] {
        list.sets.sorted { lhs, rhs in
            if lhs.setNumber == rhs.setNumber {
                return lhs.name < rhs.name
            }
            return lhs.setNumber < rhs.setNumber
        }
    }

    private let adaptiveColumns = [
        GridItem(.adaptive(minimum: 220), spacing: 16)
    ]
    private let uncategorizedSectionTitle = "Uncategorized"

    private enum SearchScope: String, CaseIterable, Identifiable {
        case sets
        case parts
        case minifigures

        var id: SearchScope { self }

        var title: String {
            switch self {
            case .sets:
                return "Sets"
            case .parts:
                return "Parts"
            case .minifigures:
                return "Minifigures"
            }
        }

        var prompt: String {
            switch self {
            case .sets:
                return "Search sets"
            case .parts:
                return "Search parts"
            case .minifigures:
                return "Search minifigures"
            }
        }
    }

    private struct SearchTaskKey: Equatable {
        let query: String
        let scope: SearchScope
    }

    private struct RefreshError: Identifiable {
        let id = UUID()
        let message: String
    }

    private var searchTaskKey: SearchTaskKey {
        SearchTaskKey(query: searchText, scope: searchScope)
    }

    var body: some View {
        Group {
            if isSearching {
                searchResultsView
            } else {
                gridView
            }
        }
        .navigationTitle(list.name)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(searchScope.prompt)
        )
        .searchScopes($searchScope, activation: .onSearchPresentation) {
            ForEach(SearchScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .task(id: searchTaskKey) {
            let key = searchTaskKey
            await performSearch(for: key)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddSetSheet = true
                    } label: {
                        Label("Add Single Set", systemImage: "plus")
                    }

                    Button {
                        showingBulkAddSheet = true
                    } label: {
                        Label("Bulk Add from File", systemImage: "tray.and.arrow.down.fill")
                    }
                } label: {
                    Label("Add Sets", systemImage: "plus")
                }
            }

        }
        .sheet(isPresented: $showingAddSetSheet) {
            AddSetView(list: list) { result in
                switch result {
                case .success:
                    try? modelContext.save()
                case .failure:
                    break
                }
            }
        }
        .sheet(isPresented: $showingBulkAddSheet) {
            BulkAddSetsView(list: list) { result in
                switch result {
                case .success:
                    try? modelContext.save()
                case .failure:
                    break
                }
            }
        }
        .sheet(item: $setBeingRenamed) { set in
            RenameSetView(set: set)
        }
        .sheet(item: $labelPrintTarget) { set in
            LabelPrintSheet(brickSet: set)
        }
        .alert(item: $refreshError) { alert in
            Alert(
                title: Text("Refresh Failed"),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var gridView: some View {
        ScrollView {
            if groupedSets.isEmpty {
                EmptyStateView(
                    icon: "shippingbox",
                    title: "No Sets Yet",
                    message: "Add a BrickLink set to this list to start tracking its parts."
                )
                .padding(.top, 80)
            } else {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(groupedSets, id: \.path) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(sectionTitle(for: group.path))
                                .font(.title3.weight(.semibold))
                                .padding(.horizontal)

                            LazyVGrid(columns: adaptiveColumns, spacing: 16) {
                                ForEach(group.sets) { set in
                                    NavigationLink(value: set) {
                                        SetCardView(brickSet: set)
                                            .overlay(alignment: .topTrailing) {
                                                if refreshingSetIDs.contains(set.persistentModelID) {
                                                    ProgressView()
                                                        .controlSize(.mini)
                                                        .padding(6)
                                                }
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button("Refresh from BrickLink", systemImage: "arrow.clockwise") {
                                            refreshInventory(for: set)
                                        }
                                        .disabled(refreshingSetIDs.contains(set.persistentModelID))
                                        Button("Print Label…", systemImage: "printer") {
                                            labelPrintTarget = set
                                        }
                                        Button("Rename", systemImage: "pencil") {
                                            setBeingRenamed = set
                                        }
                                        Button(role: .destructive) {
                                            delete(set)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .swipeActions {
                                        Button("Rename") {
                                            setBeingRenamed = set
                                        }
                                        .tint(.blue)

                                        Button(role: .destructive) {
                                            delete(set)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    @ViewBuilder
    private var searchResultsView: some View {
        if searchScope == .parts {
            partsSearchResultsList
        } else if searchScope == .minifigures {
            minifigureSearchResultsList
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    searchResultsContent
                }
                .padding(.top, 16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }

    @ViewBuilder
    private var searchResultsContent: some View {
        switch searchScope {
        case .sets:
            setsSearchResultsContent
        case .minifigures:
            EmptyView()
        case .parts:
            EmptyView()
        }
    }

    @ViewBuilder
    private var setsSearchResultsContent: some View {
        if !matchingSetsByCategory.isEmpty {
            ForEach(matchingSetsByCategory, id: \.path) { group in
                VStack(alignment: .leading, spacing: 12) {
                    Text(sectionTitle(for: group.path))
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal)

                    LazyVGrid(columns: adaptiveColumns, spacing: 16) {
                        ForEach(group.sets) { set in
                            NavigationLink(value: set) {
                                SetCardView(brickSet: set)
                                    .overlay(alignment: .topTrailing) {
                                        if refreshingSetIDs.contains(set.persistentModelID) {
                                            ProgressView()
                                                .controlSize(.mini)
                                                .padding(6)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Refresh from BrickLink", systemImage: "arrow.clockwise") {
                                    refreshInventory(for: set)
                                }
                                .disabled(refreshingSetIDs.contains(set.persistentModelID))
                                Button("Print Label…", systemImage: "printer") {
                                    labelPrintTarget = set
                                }
                                Button("Rename", systemImage: "pencil") {
                                    setBeingRenamed = set
                                }
                                Button(role: .destructive) {
                                    delete(set)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        } else {
            ContentUnavailableView.search(text: trimmedSearchText)
                .padding()
        }
    }

    private var partsSearchResultsList: some View {
        List {
            if groupedPartResults.isEmpty {
                ContentUnavailableView.search(text: trimmedSearchText)
                    .padding()
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(groupedPartResults, id: \.colorName) { group in
                    Section(group.colorName) {
                ForEach(group.entries) { entry in
                    NavigationLink(value: ContentView.SetNavigation(
                        set: entry.set,
                        searchQuery: effectiveSearchText,
                        section: entry.displayPart.inventorySection
                    )) {
                        PartSearchResultRow(
                            set: entry.set,
                            displayPart: entry.displayPart,
                            matchingParts: entry.matchingParts,
                            contextDescription: entry.contextDescription
                        )
                    }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var minifigureSearchResultsList: some View {
        List {
            if minifigureResults.isEmpty {
                ContentUnavailableView.search(text: trimmedSearchText)
                    .padding()
                    .listRowInsets(
                        EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(minifigureResults) { entry in
                    NavigationLink(value: ContentView.SetNavigation(
                        set: entry.set,
                        searchQuery: effectiveSearchText,
                        section: .regular
                    )) {
                        MinifigureSearchResultRow(
                            set: entry.set,
                            minifigure: entry.minifigure
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var groupedSets: [(path: [String], sets: [BrickSet])] {
        guard !sortedSets.isEmpty else { return [] }

        let groups = Dictionary(grouping: sortedSets) { set in
            categoryPath(for: set)
        }

        return groups
            .map { key, value in
                let orderedSets = value.sorted { lhs, rhs in
                    if lhs.setNumber != rhs.setNumber {
                        return lhs.setNumber < rhs.setNumber
                    }
                    return lhs.name < rhs.name
                }
                return (path: key, sets: orderedSets)
            }
            .sorted { lhs, rhs in
                let lhsIsUncategorized = lhs.path == [uncategorizedSectionTitle]
                let rhsIsUncategorized = rhs.path == [uncategorizedSectionTitle]

                if lhsIsUncategorized && !rhsIsUncategorized {
                    return false
                }

                if !lhsIsUncategorized && rhsIsUncategorized {
                    return true
                }

                return lhs.path.lexicographicallyPrecedes(rhs.path)
            }
    }

    private var matchingSetsByCategory: [(path: [String], sets: [BrickSet])] {
        let matches = matchingSets
        guard !matches.isEmpty else { return [] }

        let groups = Dictionary(grouping: matches) { set in
            categoryPath(for: set)
        }

        return groups
            .map { key, value in
                let orderedSets = value.sorted { lhs, rhs in
                    if lhs.setNumber != rhs.setNumber {
                        return lhs.setNumber < rhs.setNumber
                    }
                    return lhs.name < rhs.name
                }
                return (path: key, sets: orderedSets)
            }
            .sorted { lhs, rhs in
                let lhsIsUncategorized = lhs.path == [uncategorizedSectionTitle]
                let rhsIsUncategorized = rhs.path == [uncategorizedSectionTitle]

                if lhsIsUncategorized && !rhsIsUncategorized {
                    return false
                }

                if !lhsIsUncategorized && rhsIsUncategorized {
                    return true
                }

                return lhs.path.lexicographicallyPrecedes(rhs.path)
            }
    }

    private func categoryPath(for set: BrickSet) -> [String] {
        set.normalizedCategoryPath(uncategorizedTitle: uncategorizedSectionTitle)
    }

    private func sectionTitle(for path: [String]) -> String {
        path.joined(separator: " / ")
    }

    private func refreshInventory(for set: BrickSet) {
        let identifier = set.persistentModelID
        guard !refreshingSetIDs.contains(identifier) else { return }
        refreshingSetIDs.insert(identifier)

        Task {
            do {
                try await SetImportUtilities.refreshSetFromBrickLink(
                    set: set,
                    modelContext: modelContext,
                    service: brickLinkService
                )
            } catch {
                await MainActor.run {
                    refreshError = RefreshError(message: refreshErrorMessage(for: error))
                }
            }

            await MainActor.run {
                refreshingSetIDs.remove(identifier)
            }
        }
    }

    private func refreshErrorMessage(for error: Error) -> String {
        if let refreshError = error as? SetImportUtilities.RefreshError {
            return refreshError.localizedDescription
        }

        return error.localizedDescription
    }

    private func delete(_ set: BrickSet) {
        modelContext.delete(set)
        try? modelContext.save()
    }

    private var trimmedSearchText: String {
        effectiveSearchText
    }

    private var isSearching: Bool {
        !trimmedSearchText.isEmpty
    }

    private var normalizedSearchText: String {
        trimmedSearchText.lowercased()
    }

    private var matchingSets: [BrickSet] {
        guard searchScope == .sets, isSearching else { return [] }
        let normalizedQuery = normalizedSearchText
        let strippedQuery = normalizeSetNumber(normalizedQuery)
        let tokens = queryTokens(from: trimmedSearchText)

        return sortedSets.filter { set in
            let setNumberLower = set.setNumber.lowercased()
            if !normalizedQuery.isEmpty {
                if setNumberLower == normalizedQuery {
                    return true
                }

                let strippedSetNumber = normalizeSetNumber(setNumberLower)
                if !strippedQuery.isEmpty && strippedSetNumber == strippedQuery {
                    return true
                }
            }

            return matches(nameTokens: tokens, in: set.name)
        }
    }

    private func runPartSearch(for query: String) -> [PartSearchEntry] {
        let rawQuery = query.lowercased()
        guard !rawQuery.isEmpty else { return [] }

        let startsWithNumber = rawQuery.first?.isNumber == true
        let components = rawQuery.split(whereSeparator: { $0.isWhitespace })
        let primaryToken = components.first.map(String.init) ?? rawQuery
        let primaryTokenIsNumeric = primaryToken.allSatisfy { $0.isNumber }
        let numericPrefixToken = String(primaryToken.prefix { $0.isNumber })
        let dimensionPrefixQuery = normalizedDimensionPrefix(in: rawQuery)
        let shouldEnforceNumericPrefix = !numericPrefixToken.isEmpty && dimensionPrefixQuery == nil
        let normalizedQueryTokens = queryTokens(from: rawQuery)
        let secondaryTokens = normalizedQueryTokens.dropFirst()

        var builders: [PersistentIdentifier: PartSearchEntryBuilder] = [:]
        var matchOrder = 0

        for set in sortedSets {
            enumerateSearchableParts(in: set) { part, displayPart, owningMinifigure in
                let partIDLower = part.partID.lowercased()
                let colorLower = part.colorName.lowercased()
                let nameLower = part.name.lowercased()
                let searchableText = searchableText(for: part)
                let partTokens = partSearchTokens(for: part)

                if shouldEnforceNumericPrefix {
                    guard matchesNumericPartID(part.partID, numericQuery: numericPrefixToken) else { return }
                }

                if let dimensionPrefixQuery, !searchableText.contains(dimensionPrefixQuery) {
                    return
                }

                let matches: Bool
                if let dimensionPrefixQuery = dimensionPrefixQuery {
                    if normalizedQueryTokens.count <= 1 {
                        matches = true
                    } else {
                        matches = secondaryTokens.allSatisfy { token in
                            matchesToken(token, for: part, partTokens: partTokens, searchableText: searchableText)
                        }
                    }
                } else if primaryTokenIsNumeric {
                    if secondaryTokens.isEmpty {
                        matches = true
                    } else {
                        matches = secondaryTokens.allSatisfy { token in
                            matchesToken(token, for: part, partTokens: partTokens, searchableText: searchableText)
                        }
                    }
                } else if normalizedDimensionQuery(for: primaryToken) != nil {
                    matches = matchesToken(primaryToken, for: part, partTokens: partTokens, searchableText: searchableText) &&
                    secondaryTokens.allSatisfy { token in
                        matchesToken(token, for: part, partTokens: partTokens, searchableText: searchableText)
                    }
                } else if startsWithNumber {
                    guard partIDLower.hasPrefix(primaryToken) else { return }
                    if secondaryTokens.isEmpty {
                        matches = true
                    } else {
                        matches = secondaryTokens.allSatisfy { token in
                            matchesToken(token, for: part, partTokens: partTokens, searchableText: searchableText)
                        }
                    }
                } else if colorLower.contains(rawQuery) || nameLower.contains(rawQuery) {
                    matches = true
                } else {
                    matches = normalizedQueryTokens.allSatisfy { token in
                        matchesToken(token, for: part, partTokens: partTokens, searchableText: searchableText)
                    }
                }

                guard matches else { return }
                guard missingCount(for: part) > 0 else { return }

                let entrySet = part.set ?? part.minifigure?.set ?? set
                let key = displayPart.persistentModelID

                if builders[key] == nil {
                    builders[key] = PartSearchEntryBuilder(
                        set: entrySet,
                        displayPart: displayPart,
                        owningMinifigure: owningMinifigure,
                        orderIndex: matchOrder
                    )
                }

                builders[key]?.recordMatch(part, order: matchOrder)
                matchOrder += 1
            }
        }

        return builders.values
            .map { $0.build() }
            .sorted { lhs, rhs in
                if lhs.orderIndex != rhs.orderIndex {
                    return lhs.orderIndex < rhs.orderIndex
                }
                return lhs.displayPart.partID.localizedCaseInsensitiveCompare(rhs.displayPart.partID) == .orderedAscending
            }
    }

    private func runMinifigureSearch(for query: String) -> [MinifigureSearchEntry] {
        let normalizedQuery = query.lowercased()
        guard !normalizedQuery.isEmpty else { return [] }
        let tokens = queryTokens(from: query)

        return list.sets
            .flatMap { $0.minifigures }
            .compactMap { minifigure in
                let identifierLower = minifigure.identifier.lowercased()
                let matchesIdentifier = !normalizedQuery.isEmpty && identifierLower == normalizedQuery
                let matchesName = matches(nameTokens: tokens, in: minifigure.name)

                guard matchesIdentifier || matchesName else { return nil }
                guard let set = minifigure.set else { return nil }
                return MinifigureSearchEntry(set: set, minifigure: minifigure)
            }
            .sorted { lhs, rhs in
                if lhs.missingCount != rhs.missingCount {
                    return lhs.missingCount < rhs.missingCount
                }
                return lhs.minifigure.identifier.localizedCaseInsensitiveCompare(rhs.minifigure.identifier) == .orderedAscending
            }
    }

    private func matches(nameTokens tokenizedQuery: [String], in name: String) -> Bool {
        guard !tokenizedQuery.isEmpty else { return false }
        let nameTokens = queryTokens(from: name)
        return tokenizedQuery.allSatisfy { token in
            nameTokens.contains(where: { $0.hasPrefix(token) })
        }
    }

    private func queryTokens(from text: String) -> [String] {
        text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { $0.lowercased() }
    }

    private func performSearch(for key: SearchTaskKey) async {
        let trimmed = key.query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            await MainActor.run {
                effectiveSearchText = ""
                partSearchResults = []
                minifigureSearchResults = []
            }
            return
        }

        do {
            try await Task.sleep(nanoseconds: 300_000_000)
        } catch {
            return
        }

        if Task.isCancelled {
            #if DEBUG
            print("🔍 SetCollectionView search cancelled for query: '\(key.query)' scope: \(key.scope)")
            #endif
            return
        }

        await MainActor.run {
            effectiveSearchText = trimmed
            switch key.scope {
            case .parts:
                partSearchResults = runPartSearch(for: trimmed)
                minifigureSearchResults = []
            case .minifigures:
                minifigureSearchResults = runMinifigureSearch(for: trimmed)
                partSearchResults = []
            case .sets:
                partSearchResults = []
                minifigureSearchResults = []
            }
        }
    }

    private func partSearchTokens(for part: Part) -> [String] {
        let combined = "\(part.partID) \(part.colorName) \(part.name)"
        return Array(
            Set(
                queryTokens(from: combined)
            )
        )
    }

    private func matchesToken(_ token: String, for part: Part, partTokens: [String], searchableText: String) -> Bool {
        if token.allSatisfy({ $0.isNumber }) {
            if matchesNumericPartID(part.partID, numericQuery: token) {
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

    private func matchesNumericPartID(_ partID: String, numericQuery: String) -> Bool {
        guard !numericQuery.isEmpty else { return false }
        let numericPrefix = partID.prefix { $0.isNumber }
        guard !numericPrefix.isEmpty else { return false }
        return String(numericPrefix).caseInsensitiveCompare(numericQuery) == .orderedSame
    }

    private func normalizedDimensionPrefix(in query: String) -> String? {
        let prefix = query.prefix { character in
            character.isNumber || character.isWhitespace || character == "x" || character == "X" || character == "×"
        }
        guard !prefix.isEmpty else { return nil }
        return normalizedDimensionQuery(for: String(prefix))
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

    private func searchableText(for part: Part) -> String {
        let combined = "\(part.partID) \(part.colorName) \(part.name)"
            .lowercased()
            .replacingOccurrences(of: "×", with: "x")

        return combined
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func enumerateSearchableParts(
        in set: BrickSet,
        visit: (Part, Part, Minifigure?) -> Void
    ) {
        func walk(part: Part, root: Part, owningMinifigure: Minifigure?) {
            guard part.inventorySection != .extra else { return }

            visit(part, root, owningMinifigure)
            for child in part.subparts {
                walk(part: child, root: root, owningMinifigure: owningMinifigure)
            }
        }

        for part in set.parts {
            walk(part: part, root: part, owningMinifigure: nil)
        }

        for minifigure in set.minifigures {
            for part in minifigure.parts {
                walk(part: part, root: part, owningMinifigure: minifigure)
            }
        }
    }

    private var groupedPartResults: [ColorGroup] {
        let entries = partSearchResults.filter { $0.missingCount > 0 }
        guard !entries.isEmpty else { return [] }

        let grouped = Dictionary(grouping: entries) { entry in
            entry.groupingColorName
        }

        return grouped.map { key, value in
            ColorGroup(
                colorName: key,
                entries: value.sorted { lhs, rhs in
                    let nameComparison = lhs.displayPart.name.localizedCaseInsensitiveCompare(rhs.displayPart.name)
                    if nameComparison != .orderedSame {
                        return nameComparison == .orderedAscending
                    }
                    return lhs.displayPart.partID.localizedCaseInsensitiveCompare(rhs.displayPart.partID) == .orderedAscending
                }
            )
        }
        .sorted { lhs, rhs in
            lhs.colorName.localizedCaseInsensitiveCompare(rhs.colorName) == .orderedAscending
        }
    }

    private var minifigureResults: [MinifigureSearchEntry] {
        minifigureSearchResults
    }

    private func missingCount(for part: Part) -> Int {
        max(part.quantityNeeded - part.quantityHave, 0)
    }

    private func normalizeSetNumber(_ number: String) -> String {
        number.split(separator: "-").first.map(String.init) ?? number
    }

    private struct PartSearchEntry: Identifiable {
        let set: BrickSet
        let displayPart: Part
        let matchingParts: [Part]
        let owningMinifigure: Minifigure?
        let orderIndex: Int

        var id: PersistentIdentifier { displayPart.persistentModelID }

        var directMatch: Part? {
            matchingParts.first { $0.persistentModelID == displayPart.persistentModelID }
        }

        var subpartMatches: [Part] {
            matchingParts.filter { $0.persistentModelID != displayPart.persistentModelID }
        }

        var missingCount: Int {
            matchingParts.reduce(0) { $0 + max($1.quantityNeeded - $1.quantityHave, 0) }
        }

        var groupingColorName: String {
            let candidate = displayPart.colorName.isEmpty ? (subpartMatches.first?.colorName ?? displayPart.colorName) : displayPart.colorName
            let name = candidate
            return name.isEmpty ? "Unknown Color" : name
        }

        var contextDescription: String? {
            var components: [String] = []

            if !subpartMatches.isEmpty || directMatch == nil {
                let parentName = displayPart.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !parentName.isEmpty {
                    let labelPrefix: String
                    switch displayPart.inventorySection {
                    case .alternate:
                        labelPrefix = "Alternate"
                    case .counterpart:
                        labelPrefix = "Counterpart"
                    case .extra:
                        labelPrefix = "Extra"
                    case .regular:
                        labelPrefix = "Sub-Part"
                    }
                    components.append("\(labelPrefix): \(parentName)")
                }
            }

            if let owningMinifigure {
                components.append("Minifigure: \(owningMinifigure.name)")
            }

            return components.isEmpty ? nil : components.joined(separator: " • ")
        }
    }

    private struct PartSearchEntryBuilder {
        let set: BrickSet
        let displayPart: Part
        let owningMinifigure: Minifigure?
        private(set) var matchingParts: [Part] = []
        private var recordedIDs: Set<PersistentIdentifier> = []
        private(set) var orderIndex: Int

        init(
            set: BrickSet,
            displayPart: Part,
            owningMinifigure: Minifigure?,
            orderIndex: Int
        ) {
            self.set = set
            self.displayPart = displayPart
            self.owningMinifigure = owningMinifigure
            self.matchingParts = []
            self.recordedIDs = []
            self.orderIndex = orderIndex
        }

        mutating func recordMatch(_ part: Part, order: Int) {
            if order < orderIndex {
                orderIndex = order
            }

            let identifier = part.persistentModelID
            guard !recordedIDs.contains(identifier) else { return }

            recordedIDs.insert(identifier)
            matchingParts.append(part)
        }

        func build() -> PartSearchEntry {
            PartSearchEntry(
                set: set,
                displayPart: displayPart,
                matchingParts: matchingParts,
                owningMinifigure: owningMinifigure,
                orderIndex: orderIndex
            )
        }
    }

    private struct MinifigureSearchEntry: Identifiable {
        let set: BrickSet
        let minifigure: Minifigure

        var missingCount: Int {
            max(minifigure.quantityNeeded - minifigure.quantityHave, 0)
        }

        var id: PersistentIdentifier { minifigure.persistentModelID }
    }

    private struct ColorGroup {
        let colorName: String
        let entries: [PartSearchEntry]
    }

    private struct PartThumbnail: View {
        let url: URL?

        var body: some View {
            Group {
                if let url {
                    ThumbnailImage(url: url) { phase in
                        switch phase {
                        case .empty, .loading:
                            ProgressView()
                                .frame(width: 80, height: 60)
                        case .success(let image):
                            image
                                .frame(width: 80, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        case .failure(let state):
                            if shouldShowRetry(for: state.error) {
                                ZStack {
                                    placeholder
                                    VStack(spacing: 6) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.red)
                                        Button("Retry") {
                                            state.retry()
                                        }
                                        .font(.caption)
                                    }
                                    .padding(8)
                                }
                            } else {
                                placeholder
                            }
                        }
                    }
                    .background(.white)
                } else {
                    placeholder
                }
            }
            .frame(width: 80, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

        private func shouldShowRetry(for error: Error) -> Bool {
            if let cacheError = error as? ThumbnailCacheError,
               cacheError.isMissingAssetError {
                return false
            }

            if let urlError = error as? URLError,
               urlError.code == .fileDoesNotExist {
                return false
            }

            return true
        }
    }

    private struct MinifigureThumbnail: View {
        let url: URL?

        var body: some View {
            Group {
                if let url {
                    ThumbnailImage(url: url) { phase in
                        switch phase {
                        case .empty, .loading:
                            ProgressView()
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .failure(let state):
                            ZStack {
                                placeholder
                                VStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.red)
                                    Button("Retry") {
                                        state.retry()
                                    }
                                    .font(.caption)
                                }
                                .padding(8)
                            }
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }

        private var placeholder: some View {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
                .overlay {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                }
        }
    }

}

private extension ThumbnailCacheError {
    var isMissingAssetError: Bool {
        switch self {
        case .invalidResponse(let statusCode):
            if let statusCode {
                return statusCode == 404 || statusCode == 410
            }
            return false
        case .emptyData:
            return true
        case .managerDeallocated:
            return false
        }
    }
}

#Preview("Sets Grid") {
    let container = SwiftLEGOModelContainer.preview
    let list = try! ModelContext(container)
        .fetch(FetchDescriptor<CollectionList>())
        .first!

    return NavigationStack {
        SetCollectionView(list: list)
    }
    .modelContainer(container)
}
