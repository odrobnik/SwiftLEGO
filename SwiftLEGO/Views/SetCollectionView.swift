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

    init(list: CollectionList, onNavigate: @escaping (ContentView.Destination) -> Void = { _ in }) {
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

    var body: some View {
        Group {
            if isSearching {
                searchResultsView
            } else {
                gridView
            }
        }
        .navigationTitle(list.name)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Part ID")
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
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: adaptiveColumns, spacing: 16) {
                ForEach(sortedSets) { set in
                    Button {
                        onNavigate(.set(set.persistentModelID))
                    } label: {
                        SetCardView(brickSet: set)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
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
            .padding()

            if sortedSets.isEmpty {
                EmptyStateView(
                    icon: "shippingbox",
                    title: "No Sets Yet",
                    message: "Add a BrickLink set to this list to start tracking its parts."
                )
                .padding(.top, 80)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var searchResultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if !matchingSets.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Sets")
                            .font(.title2.weight(.semibold))
                            .padding(.horizontal)

                        LazyVGrid(columns: adaptiveColumns, spacing: 16) {
                            ForEach(matchingSets, id: \.persistentModelID) { set in
                                Button {
                                    onNavigate(.set(set.persistentModelID))
                                } label: {
                                    SetCardView(brickSet: set)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                if !setsMissingPart.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sets Missing Copies")
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal)

                    VStack(spacing: 16) {
                        ForEach(setsMissingPart) { entry in
                            SearchResultRow(entry: entry) {
                                onNavigate(.filteredSet(entry.set.persistentModelID, partID: trimmedSearchText))
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }

            if !setsCompletePart.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sets Complete")
                        .font(.title2.weight(.semibold))
                        .padding(.horizontal)

                    VStack(spacing: 16) {
                        ForEach(setsCompletePart) { entry in
                            SearchResultRow(entry: entry, highlightMissing: false) {
                                onNavigate(.set(entry.set.persistentModelID))
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }

                if matchingSets.isEmpty && setsMissingPart.isEmpty && setsCompletePart.isEmpty {
                    ContentUnavailableView.search(text: trimmedSearchText)
                        .padding()
                }
            }
            .padding(.top, 16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func delete(_ set: BrickSet) {
        modelContext.delete(set)
        try? modelContext.save()
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedSearchText.isEmpty
    }

    private var normalizedSearchText: String {
        trimmedSearchText.lowercased()
    }

    private var matchingSets: [BrickSet] {
        guard isSearching else { return [] }
        let normalizedQuery = normalizedSearchText
        let strippedQuery = normalizeSetNumber(normalizedQuery)
        let queryHasHyphen = normalizedQuery.contains("-")

        return sortedSets.filter { set in
            let setNumberLower = set.setNumber.lowercased()
            if setNumberLower == normalizedQuery {
                return true
            }

            let strippedSetNumber = normalizeSetNumber(setNumberLower)
            if !queryHasHyphen && !strippedQuery.isEmpty && strippedSetNumber == strippedQuery {
                return true
            }

            return false
        }
    }

    private var matchingParts: [Part] {
        guard isSearching else { return [] }
        return list.sets.flatMap { set in
            set.parts.filter { part in
                part.partID.compare(trimmedSearchText, options: .caseInsensitive) == .orderedSame
            }
        }
    }

    private var searchEntries: [SearchEntry] {
        matchingParts.compactMap { part in
            guard let set = part.set else { return nil }
            return SearchEntry(set: set, part: part, missingCount: missingCount(for: part))
        }
    }

    private var setsMissingPart: [SearchEntry] {
        searchEntries.filter { $0.missingCount > 0 }
            .sorted { lhs, rhs in
                if lhs.missingCount == rhs.missingCount {
                    return lhs.set.name < rhs.set.name
                }
                return lhs.missingCount < rhs.missingCount
            }
    }

    private var setsCompletePart: [SearchEntry] {
        searchEntries.filter { $0.missingCount == 0 }
            .sorted { lhs, rhs in
                lhs.set.name < rhs.set.name
            }
    }

    private func missingCount(for part: Part) -> Int {
        max(part.quantityNeeded - part.quantityHave, 0)
    }

    private func setName(for part: Part) -> String {
        part.set?.name ?? "Unknown Set"
    }

    private func normalizeSetNumber(_ number: String) -> String {
        number.split(separator: "-").first.map(String.init) ?? number
    }

    private struct SearchEntry: Identifiable {
        let set: BrickSet
        let part: Part
        let missingCount: Int

        var id: PersistentIdentifier { part.persistentModelID }
    }

    private struct SetSearchRow: View {
        let set: BrickSet
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                SetCardView(brickSet: set)
            }
            .buttonStyle(.plain)
        }
    }

    private struct SearchResultRow: View {
        let entry: SearchEntry
        var highlightMissing: Bool = true
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        PartThumbnail(url: entry.part.imageURL)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.set.name)
                                .font(.headline)

                            Text(entry.set.setNumber)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text("\(entry.part.partID) • \(entry.part.colorName)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if highlightMissing {
                        Text("Missing \(entry.missingCount) • Need \(entry.part.quantityNeeded), have \(entry.part.quantityHave)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(entry.missingCount > 0 ? .orange : .green)
                    } else {
                        Text("Complete • Need \(entry.part.quantityNeeded), have \(entry.part.quantityHave)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.green)
                    }
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
    }

    private struct PartThumbnail: View {
        let url: URL?

        var body: some View {
            Group {
                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .failure:
                            placeholder
                        @unknown default:
                            placeholder
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
                    Image(systemName: "cube.transparent")
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
