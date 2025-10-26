import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(animation: .default) private var lists: [CollectionList]
    @State private var path = NavigationPath()
    @State private var selectedListID: PersistentIdentifier?
    @State private var selectedCategoryPath: [String]?
    @State private var setCollectionSearchText: String = ""
    private let uncategorizedCategoryTitle = "Uncategorized"

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.automatic)) {
            ListSidebarView(
                selectionID: bindingSelectedListID,
                selectedCategoryPath: $selectedCategoryPath,
                onSetSelected: handleSidebarSetSelection(_:),
                onCategorySelected: handleSidebarCategorySelection(_:)
            )
                .background(Color(uiColor: .systemGroupedBackground))
        } detail: {
            NavigationStack(path: $path) {
                Group {
                    if let categoryPath = selectedCategoryPath {
                        CategorySetsView(
                            categoryPath: categoryPath,
                            sets: setsMatchingCategory(path: categoryPath)
                        )
                        .id(categoryPath.joined(separator: "|"))
                    } else if let list = selectedList {
                        SetCollectionView(list: list, searchText: $setCollectionSearchText)
                        .id(list.persistentModelID)
                    } else if let first = lists.first {
                        SetCollectionView(list: first, searchText: $setCollectionSearchText)
                        .task { setSelectedList(first) }
                    } else {
                        EmptyStateView(
                            icon: "square.stack.3d.up.slash",
                            title: "No Lists Yet",
                            message: "Create a list to start organizing your LEGO sets."
                        )
                    }
                }
                .navigationDestination(for: BrickSet.self) { set in
                    SetDetailView(brickSet: set, searchText: setCollectionSearchText)
                }
                .navigationDestination(for: SearchResult.self) { result in
                    SetDetailView(
                        brickSet: result.set,
                        searchText: result.searchQuery,
                        initialSection: result.section
                    )
                    .environment(\.setDetailShouldPropagateSearchFilter, true)
                }
                .navigationDestination(for: Minifigure.self) { minifigure in
                    MinifigureDetailView(minifigure: minifigure)
                }
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

    private func handleSidebarSetSelection(_ set: BrickSet) {
        guard let list = set.collection else { return }
        setSelectedList(list)
        path = NavigationPath()
        path.append(set)
    }

    private func handleSidebarCategorySelection(_ pathComponents: [String]?) {
        selectedCategoryPath = pathComponents
        if pathComponents != nil {
            selectedListID = nil
        } else {
            ensureSelection()
        }
        path = NavigationPath()
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

}

#Preview("App Root") {
    ContentView()
        .modelContainer(SwiftLEGOModelContainer.preview)
}
