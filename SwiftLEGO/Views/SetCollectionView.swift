import SwiftUI
import SwiftData

struct SetCollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var list: CollectionList
    let onNavigate: (ContentView.Destination) -> Void
    @State private var showingAddSetSheet = false
    @State private var showingBulkAddSheet = false
    @State private var setBeingRenamed: BrickSet?
    @State private var searchText: String = ""
    @State private var searchScope: SearchScope = .sets
    @State private var effectiveSearchText: String = ""
    @State private var labelPrintTarget: BrickSet?
    @State private var partSearchResults: [PartSearchEntry] = []
    @State private var minifigureSearchResults: [MinifigureSearchEntry] = []

    init(
        list: CollectionList,
        onNavigate: @escaping (ContentView.Destination) -> Void = { _ in }
    ) {
        self._list = Bindable(list)
        self.onNavigate = onNavigate
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
        .searchScopes($searchScope) {
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
                                    Button {
                                        onNavigate(.set(set.persistentModelID))
                                    } label: {
                                        SetCardView(brickSet: set)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
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
            minifigureSearchResultsContent
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
                            Button {
                                onNavigate(.set(set.persistentModelID))
                            } label: {
                                SetCardView(brickSet: set)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
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
                    PartSearchResultRow(
                        set: entry.set,
                        part: entry.part,
                        containerDescription: entry.containerDescription,
                        onShowSet: {
                            onNavigate(
                                .filteredSet(
                                    entry.set.persistentModelID,
                                    partID: entry.displayPart.partID,
                                    colorID: entry.displayPart.colorID,
                                    query: effectiveSearchText
                                )
                            )
                        }
                    )
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    @ViewBuilder
    private var minifigureSearchResultsContent: some View {
        if !minifigureResults.isEmpty {
            VStack(spacing: 16) {
                ForEach(minifigureResults) { entry in
                    MinifigureSearchResultRow(entry: entry) {
                        onNavigate(.set(entry.set.persistentModelID))
                    }
                }
            }
            .padding(.horizontal)
        } else {
            ContentUnavailableView.search(text: trimmedSearchText)
                .padding()
        }
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
        let normalizedQueryTokens = queryTokens(from: rawQuery)
        let secondaryTokens = normalizedQueryTokens.dropFirst()

        var results: [PartSearchEntry] = []

        for set in sortedSets {
            enumerateSearchableParts(in: set) { part, displayPart, owningMinifigure in
                let partIDLower = part.partID.lowercased()
                let colorLower = part.colorName.lowercased()
                let nameLower = part.name.lowercased()
                let partTokens = partSearchTokens(for: part)

                let matches: Bool
                if startsWithNumber {
                    guard partIDLower.hasPrefix(primaryToken) else { return }
                    if secondaryTokens.isEmpty {
                        matches = true
                    } else {
                        matches = secondaryTokens.allSatisfy { token in
                            partTokens.contains(where: { $0.hasPrefix(token) || $0.contains(token) })
                        }
                    }
                } else if colorLower.contains(rawQuery) || nameLower.contains(rawQuery) {
                    matches = true
                } else {
                    matches = normalizedQueryTokens.allSatisfy { token in
                        partTokens.contains(where: { $0.hasPrefix(token) || $0.contains(token) })
                    }
                }

                guard matches else { return }
                guard missingCount(for: part) > 0 else { return }
                let entrySet = part.set ?? part.minifigure?.set ?? set
                let entry = PartSearchEntry(
                    set: entrySet,
                    part: part,
                    displayPart: displayPart,
                    owningMinifigure: owningMinifigure,
                    orderIndex: results.count
                )
                results.append(entry)
            }
        }

        return results
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
            entry.part.colorName.isEmpty ? "Unknown Color" : entry.part.colorName
        }

        return grouped.map { key, value in
            ColorGroup(
                colorName: key,
                entries: value.sorted { lhs, rhs in
                    let nameComparison = lhs.part.name.localizedCaseInsensitiveCompare(rhs.part.name)
                    if nameComparison != .orderedSame {
                        return nameComparison == .orderedAscending
                    }
                    return lhs.part.partID.localizedCaseInsensitiveCompare(rhs.part.partID) == .orderedAscending
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
        let part: Part
        let displayPart: Part
        let owningMinifigure: Minifigure?
        let orderIndex: Int

        var missingCount: Int {
            max(part.quantityNeeded - part.quantityHave, 0)
        }

        var containerDescription: String? {
            var components: [String] = []

            if displayPart.persistentModelID != part.persistentModelID {
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

        var id: PersistentIdentifier { part.persistentModelID }
    }

    private struct PartSearchResultRow: View {
        @Environment(\.modelContext) private var modelContext
        let set: BrickSet
        @Bindable var part: Part
        let containerDescription: String?
        let onShowSet: (() -> Void)?

        private var missingCount: Int {
            max(part.quantityNeeded - part.quantityHave, 0)
        }

        private var quantityBinding: Binding<Int> {
            Binding(
                get: { part.quantityHave },
                set: { updateQuantity(to: $0) }
            )
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 16) {
                    PartThumbnail(url: part.imageURL)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(part.name)
                            .font(.headline)

                        Text("\(part.partID) • \(part.colorName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .center, spacing: 6) {
                        Text("\(part.quantityHave) of \(part.quantityNeeded)")
                            .font(.title3.bold())
                            .contentTransition(.numericText())
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)

                        Stepper("", value: quantityBinding, in: 0...part.quantityNeeded)
                            .labelsHidden()
                    }
                    .frame(width: 150, alignment: .trailing)
            }

            HStack(alignment: .center, spacing: 12) {
                Text("Missing \(missingCount) • Need \(part.quantityNeeded), have \(part.quantityHave)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if let containerDescription {
                        Text(containerDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let onShowSet {
                        Button(action: onShowSet) {
                            HStack(spacing: 6) {
                                Text("\(set.setNumber) • \(set.name)")
                                    .font(.body)
                                Image(systemName: "arrow.up.right.square")
                                    .imageScale(.medium)
                            }
                            .padding(.vertical, 2)
                            .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Text("\(set.setNumber) • \(set.name)")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .systemBackground))
            )
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

        private func updateQuantity(to newValue: Int) {
            let clamped = max(0, min(newValue, part.quantityNeeded))
            guard clamped != part.quantityHave else { return }

            let applyChange = {
                part.quantityHave = clamped
                try? modelContext.save()
            }

            if clamped >= part.quantityNeeded {
                withAnimation(.easeInOut) {
                    applyChange()
                }
            } else {
                withAnimation {
                    applyChange()
                }
            }
        }

        private func markComplete() {
            updateQuantity(to: part.quantityNeeded)
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

    private struct MinifigureSearchResultRow: View {
        let entry: MinifigureSearchEntry
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        MinifigureThumbnail(url: entry.minifigure.imageURL)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.minifigure.name)
                                .font(.headline)

                            Text(entry.minifigure.identifier)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text("\(entry.set.name) • \(entry.set.setNumber)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    let missingCount = entry.missingCount
                    Text(statusText(for: missingCount, minifigure: entry.minifigure))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(missingCount > 0 ? .orange : .green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 8)
                )
            }
            .buttonStyle(.plain)
        }

        private func statusText(for missingCount: Int, minifigure: Minifigure) -> String {
            if missingCount > 0 {
                return "Missing \(missingCount) • Need \(minifigure.quantityNeeded), have \(minifigure.quantityHave)"
            } else {
                return "Complete • Need \(minifigure.quantityNeeded), have \(minifigure.quantityHave)"
            }
        }
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
