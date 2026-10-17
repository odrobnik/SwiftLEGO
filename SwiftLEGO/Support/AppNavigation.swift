import SwiftUI
import SwiftData
import BrickCore

/// What the detail column shows, and the navigation stack pushed on top of it. The
/// root view owns it; the sidebar and its rows read it from the environment.
@MainActor
@Observable
final class AppNavigation {
    enum Selection: Hashable {
        case list(PersistentIdentifier)
        case order(PersistentIdentifier)
        case category([String])
    }

    var selection: Selection?
    var path = NavigationPath()

    var selectedCategoryPath: [String]? {
        if case .category(let path) = selection {
            return path
        }
        return nil
    }

    /// Shows `selection` in the detail column and pops whatever was pushed on top of
    /// it, also when it is already selected.
    func select(_ selection: Selection?) {
        self.selection = selection
        path = NavigationPath()
    }

    /// Deletes `list`, clearing the selection first if it shows the list.
    func delete(_ list: CollectionList, in modelContext: ModelContext) {
        if selection == .list(list.persistentModelID) {
            select(nil)
        }
        modelContext.delete(list)
        try? modelContext.save()
    }

    /// Deletes `order`, clearing the selection first if it shows the order.
    func delete(_ order: BrickOrder, in modelContext: ModelContext) {
        if selection == .order(order.persistentModelID) {
            select(nil)
        }
        modelContext.delete(order)
        try? modelContext.save()
    }
}
