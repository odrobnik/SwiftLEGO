import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(animation: .default) private var lists: [CollectionList]
    @State private var path: [Destination] = []
    @State private var selectedListID: PersistentIdentifier?
    @State private var selectedCategoryPath: [String]?
    private let uncategorizedCategoryTitle = "Uncategorized"

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.automatic)) {
            ListSidebarView(
                selectionID: bindingSelectedListID,
                selectedCategoryPath: $selectedCategoryPath,
                onSetSelected: handleSidebarSetSelection(_:),
                onCategorySelected: handleSidebarCategorySelection(_:),
                selectedSetID: currentSelectedSetID
            )
                .background(Color(uiColor: .systemGroupedBackground))
        } detail: {
            NavigationStack(path: $path) {
                Group {
                    if let categoryPath = selectedCategoryPath {
                        CategorySetsView(
                            categoryPath: categoryPath,
                            sets: setsMatchingCategory(path: categoryPath),
                            selectedSetID: currentSelectedSetID
                        ) { destination in
                            path.append(destination)
                        }
                        .id(categoryPath.joined(separator: "|"))
                    } else if let list = selectedList {
                        SetCollectionView(list: list) { destination in
                            path.append(destination)
                        }
                        .id(list.persistentModelID)
                    } else if let first = lists.first {
                        SetCollectionView(list: first) { destination in
                            path.append(destination)
                        }
                        .task { setSelectedList(first) }
                    } else {
                        EmptyStateView(
                            icon: "square.stack.3d.up.slash",
                            title: "No Lists Yet",
                            message: "Create a list to start organizing your LEGO sets."
                        )
                    }
                }
                .navigationDestination(for: Destination.self, destination: makeDestination)
            }
        }
        .onChange(of: lists.count) { _, _ in
            ensureSelection()
        }
        .task {
            ensureSelection()
        }
    }
    
    private var bindingSelectedListID: Binding<PersistentIdentifier?> {
        Binding(get: { selectedListID }, set: { newID in
            selectedListID = newID
            if newID != nil {
                selectedCategoryPath = nil
            }
        })
    }
    
    private var selectedList: CollectionList? {
        guard let selectedListID else { return nil }
        return lists.first(where: { $0.persistentModelID == selectedListID })
    }
    
    private func ensureSelection() {
        if selectedCategoryPath != nil { return }

        if selectedListID == nil {
            setSelectedList(lists.first)
        } else if selectedList == nil {
            setSelectedList(lists.first)
        }
    }
    
    private func setSelectedList(_ list: CollectionList?) {
        if list != nil {
            selectedCategoryPath = nil
        }
        selectedListID = list?.persistentModelID
    }

    private var currentSelectedSetID: PersistentIdentifier? {
        guard let last = path.last else { return nil }
        switch last {
        case .set(let destination):
            return destination.id
        case .minifigure(let destination):
            return destination.setID
        }
    }

    private func handleSidebarSetSelection(_ set: BrickSet) {
        guard let list = set.collection else { return }
        setSelectedList(list)
        path = [.set(.init(id: set.persistentModelID))]
    }

    private func handleSidebarCategorySelection(_ pathComponents: [String]?) {
        selectedCategoryPath = pathComponents
        if pathComponents != nil {
            selectedListID = nil
        } else {
            ensureSelection()
        }
        path.removeAll()
    }
    
    @ViewBuilder
    private func makeDestination(_ destination: Destination) -> some View {
        switch destination {
        case .set(let payload):
            if let set = fetchSet(with: payload.id) {
                SetDetailView(
                    brickSet: set,
                    initialSearchText: payload.searchQuery
                )
            } else {
                Text("Set unavailable")
                    .foregroundStyle(.secondary)
            }
        case .minifigure(let payload):
            if let minifigure = fetchMinifigure(with: payload.minifigureID) {
                MinifigureDetailView(minifigure: minifigure)
            } else {
                Text("Minifigure unavailable")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func setsMatchingCategory(path: [String]) -> [BrickSet] {
        lists
            .flatMap { $0.sets }
            .filter { categoryMatches($0, path: path) }
    }

    private func categoryMatches(_ set: BrickSet, path: [String]) -> Bool {
        let normalized = categoryPath(for: set)

        if path == [uncategorizedCategoryTitle] {
            return normalized == [uncategorizedCategoryTitle]
        }

        return normalized.starts(with: path)
    }

    private func categoryPath(for set: BrickSet) -> [String] {
        var path = set.normalizedCategoryPath(uncategorizedTitle: uncategorizedCategoryTitle)

        if path.isEmpty {
            path = [uncategorizedCategoryTitle]
        }

        return path
    }

    private func fetchSet(with id: PersistentIdentifier) -> BrickSet? {
        for list in lists {
            if let match = list.sets.first(where: { $0.persistentModelID == id }) {
                return match
            }
        }
        return nil
    }

    private func fetchMinifigure(with id: PersistentIdentifier) -> Minifigure? {
        for list in lists {
            for set in list.sets {
                if let match = set.minifigures.first(where: { $0.persistentModelID == id }) {
                    return match
                }
            }
        }
        return nil
    }

}

extension ContentView {
    enum Destination: Hashable {
        case set(SetDestination)
        case minifigure(MinifigureDestination)
    }

    struct SetDestination: Hashable {
        let id: PersistentIdentifier
        var partID: String?
        var colorID: String?
        var searchQuery: String?

        init(
            id: PersistentIdentifier,
            partID: String? = nil,
            colorID: String? = nil,
            searchQuery: String? = nil
        ) {
            self.id = id
            self.partID = partID
            self.colorID = colorID
            self.searchQuery = searchQuery
        }
    }

    struct MinifigureDestination: Hashable {
        let setID: PersistentIdentifier
        let minifigureID: PersistentIdentifier
    }
}

#Preview("App Root") {
    ContentView()
        .modelContainer(SwiftLEGOModelContainer.preview)
}
