#if canImport(BrickCore)
import BrickCore
#endif
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(animation: .default) private var lists: [CollectionList]
    @Query(animation: .default) private var orders: [BrickOrder]
    @State private var navigation = AppNavigation()

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.automatic)) {
            ListSidebarView()
                .background(Color(uiColor: .systemGroupedBackground))
        } detail: {
            NavigationStack(path: $navigation.path) {
                Group {
                    switch navigation.selection {
                    case .category(let categoryPath):
                        CategorySetsRoot(categoryPath: categoryPath)
                            .id(categoryPath.joined(separator: "|"))
                    case .order(let orderID):
                        if let order = orders.first(where: { $0.persistentModelID == orderID }) {
                            OrderDetailView(order: order)
                                .id(order.persistentModelID)
                        }
                    case .list(let listID):
                        if let list = lists.first(where: { $0.persistentModelID == listID }) {
                            SetCollectionView(list: list)
                                .id(list.persistentModelID)
                        }
                    case nil:
                        if let first = lists.first {
                            SetCollectionView(list: first)
                                .task { navigation.selection = .list(first.persistentModelID) }
                        } else if let firstOrder = orders.first {
                            OrderDetailView(order: firstOrder)
                                .task { navigation.selection = .order(firstOrder.persistentModelID) }
                        } else {
                            EmptyStateView(
                                icon: "square.stack.3d.up.slash",
                                title: "No Lists Yet",
                                message: "Create a list to start organizing your LEGO sets."
                            )
                        }
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
                        initialSearchText: result.searchQuery,
                        initialSection: result.section
                    )
                    .environment(\.setDetailShouldPropagateSearchFilter, true)
                }
                .navigationDestination(for: Minifigure.self) { minifigure in
                    MinifigureDetailView(minifigure: minifigure)
                }
            }
        }
        .environment(navigation)
        .onChange(of: lists.count) { _, _ in
            ensureSelection()
        }
        .onChange(of: orders.count) { _, _ in
            ensureSelection()
        }
        .task {
            ensureSelection()
            #if canImport(BrickCore)
            await BrickColorRefreshManager.shared.refreshIfNeeded(using: modelContext)
            #endif
        }
    }

    /// Replaces a selection whose list or order no longer exists, and a category
    /// selection once the last list is gone, with the first list or order.
    private func ensureSelection() {
        switch navigation.selection {
        case .category:
            if !lists.isEmpty { return }
        case .order(let orderID):
            if orders.contains(where: { $0.persistentModelID == orderID }) { return }
        case .list(let listID):
            if lists.contains(where: { $0.persistentModelID == listID }) { return }
        case nil:
            break
        }

        if let firstList = lists.first {
            navigation.select(.list(firstList.persistentModelID))
        } else if let firstOrder = orders.first {
            navigation.select(.order(firstOrder.persistentModelID))
        } else {
            navigation.select(nil)
        }
    }
}

/// The sets of a sidebar category. Matching them here rather than in `ContentView`
/// keeps the root view from depending on the categories of every set.
private struct CategorySetsRoot: View {
    @Query(animation: .default) private var lists: [CollectionList]
    let categoryPath: [String]

    var body: some View {
        CategorySetsView(
            categoryPath: categoryPath,
            sets: Self.sets(in: lists, matching: categoryPath)
        )
    }

    private static func sets(in lists: [CollectionList], matching categoryPath: [String]) -> [BrickSet] {
        let path = CategoryConstants.pathBelowRoot(categoryPath)
        let allSets = lists.flatMap(\.sets)
        guard !path.isEmpty else { return allSets }

        let uncategorized = [CategoryConstants.uncategorizedTitle]

        return allSets.filter { set in
            let normalizedPath = set.normalizedCategoryPath(uncategorizedTitle: CategoryConstants.uncategorizedTitle)
            let setPath = normalizedPath.isEmpty ? uncategorized : normalizedPath

            if path == uncategorized {
                return setPath == uncategorized
            }

            return setPath.starts(with: path)
        }
    }
}

#Preview("App Root") {
    ContentView()
        .modelContainer(SwiftLEGOModelContainer.preview)
}
