import Foundation
import SwiftData

@Model
final class SetCategory: Identifiable {
    @Attribute(.unique) var id: UUID
    var categoryID: String?
    var name: String
    var sortOrder: Int
    var set: BrickSet?

    init(
        id: UUID = UUID(),
        categoryID: String? = nil,
        name: String,
        sortOrder: Int,
        set: BrickSet? = nil
    ) {
        self.id = id
        self.categoryID = categoryID
        self.name = name
        self.sortOrder = sortOrder
        self.set = set
    }
}

extension Array where Element == SetCategory {
    func sortedByOrder() -> [SetCategory] {
        sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.name < rhs.name
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }
}
