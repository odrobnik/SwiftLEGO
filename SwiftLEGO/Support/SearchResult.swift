import Foundation
import SwiftData
#if canImport(BrickCore)
import BrickCore
#endif

struct SearchResult: Hashable {
    let set: BrickSet
    let searchQuery: String
    let section: Part.InventorySection?

    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.set.persistentModelID == rhs.set.persistentModelID &&
        lhs.searchQuery == rhs.searchQuery &&
        lhs.section == rhs.section
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(set.persistentModelID)
        hasher.combine(searchQuery)
        hasher.combine(section)
    }
}
