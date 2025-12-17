#if canImport(BrickCore)
import BrickCore
#endif
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(animation: .default) private var lists: [CollectionList]
    @Query(animation: .default) private var orders: [BrickOrder]
    @State private var path = NavigationPath()
    @State private var selectedListID: PersistentIdentifier?
    @State private var selectedOrderID: PersistentIdentifier?
    @State private var selectedCategoryPath: [String]?
    private let uncategorizedCategoryTitle = "Uncategorized"
    private let rootCategoryTitle = CategoryConstants.rootCategoryTitle

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.automatic)) {
            ListSidebarView(
                selectionID: bindingSelectedListID,
                selectedOrderID: $selectedOrderID,
                selectedCategoryPath: $selectedCategoryPath,
                onSetSelected: handleSidebarSetSelection(_:),
                onCategorySelected: handleSidebarCategorySelection(_:),
                onOrderSelected: handleSidebarOrderSelection(_:)
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
                    } else if let order = selectedOrder {
                        OrderDetailView(order: order)
                            .id(order.persistentModelID)
                    } else if let list = selectedList {
                        SetCollectionView(list: list)
                        .id(list.persistentModelID)
                    } else if let first = lists.first {
                        SetCollectionView(list: first)
                        .task { setSelectedList(first) }
                    } else if let firstOrder = orders.first {
                        OrderDetailView(order: firstOrder)
                            .task { setSelectedOrder(firstOrder) }
                    } else {
                        EmptyStateView(
                            icon: "square.stack.3d.up.slash",
                            title: "No Lists Yet",
                            message: "Create a list to start organizing your LEGO sets."
                        )
                    }
                }
                .navigationDestination(for: BrickSet.self) { set in
                    SetDetailView(brickSet: set)
                }
                .navigationDestination(for: OrderPartRoute.self) { route in
                    OrderPartDistributionView(
                        orderPart: route.orderPart,
                        searchQuery: route.searchQuery
                    )
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
        .onChange(of: orders.count) { _, _ in
            ensureSelection()
        }
        .task {
            #if canImport(BrickCore)
            await BrickColorRefreshManager.shared.refreshIfNeeded(using: modelContext)
            #endif
            ensureSelection()
        }
    }
    
    private var bindingSelectedListID: Binding<PersistentIdentifier?> {
        Binding(get: { selectedListID }, set: { newID in
            selectedListID = newID
            if newID != nil {
                selectedCategoryPath = nil
                selectedOrderID = nil
            }
        })
    }
    
    private var selectedList: CollectionList? {
        guard let selectedListID else { return nil }
        return lists.first(where: { $0.persistentModelID == selectedListID })
    }

    private var selectedOrder: BrickOrder? {
        guard let selectedOrderID else { return nil }
        return orders.first(where: { $0.persistentModelID == selectedOrderID })
    }
    
    private func ensureSelection() {
        if selectedCategoryPath != nil { return }
        if let selectedOrderID, orders.contains(where: { $0.persistentModelID == selectedOrderID }) {
            return
        }
        if let selectedListID, lists.contains(where: { $0.persistentModelID == selectedListID }) {
            return
        }

        if let firstList = lists.first {
            setSelectedList(firstList)
        } else if let firstOrder = orders.first {
            setSelectedOrder(firstOrder)
        } else {
            selectedListID = nil
            selectedOrderID = nil
        }
    }
    
    private func setSelectedList(_ list: CollectionList?) {
        if list != nil {
            selectedCategoryPath = nil
        }
        selectedListID = list?.persistentModelID
        if list != nil {
            selectedOrderID = nil
        }
    }

    private func setSelectedOrder(_ order: BrickOrder?) {
        if order != nil {
            selectedCategoryPath = nil
            selectedListID = nil
        }
        selectedOrderID = order?.persistentModelID
    }

    private func handleSidebarSetSelection(_ set: BrickSet) {
        guard let list = set.collection else { return }
        setSelectedList(list)
        selectedOrderID = nil
        path = NavigationPath()
        path.append(set)
    }

    private func handleSidebarCategorySelection(_ pathComponents: [String]?) {
        selectedCategoryPath = pathComponents
        if pathComponents != nil {
            selectedListID = nil
            selectedOrderID = nil
        } else {
            ensureSelection()
        }
        path = NavigationPath()
    }

    private func handleSidebarOrderSelection(_ order: BrickOrder) {
        setSelectedOrder(order)
        path = NavigationPath()
    }
    private func setsMatchingCategory(path: [String]) -> [BrickSet] {
        lists
            .flatMap { $0.sets }
            .filter { categoryMatches($0, path: path) }
    }

    private func categoryMatches(_ set: BrickSet, path: [String]) -> Bool {
        let effectivePath = normalizedPath(for: path)
        let normalized = categoryPath(for: set)

        if effectivePath.isEmpty {
            return true
        }

        if effectivePath == [uncategorizedCategoryTitle] {
            return normalized == [uncategorizedCategoryTitle]
        }

        return normalized.starts(with: effectivePath)
    }

    private func categoryPath(for set: BrickSet) -> [String] {
        var path = set.normalizedCategoryPath(uncategorizedTitle: uncategorizedCategoryTitle)

        if path.isEmpty {
            path = [uncategorizedCategoryTitle]
        }

        return path
    }

    private func normalizedPath(for path: [String]) -> [String] {
        if path.first == rootCategoryTitle {
            return Array(path.dropFirst())
        }

        return path
    }

}

#Preview("App Root") {
    ContentView()
        .modelContainer(SwiftLEGOModelContainer.preview)
}
