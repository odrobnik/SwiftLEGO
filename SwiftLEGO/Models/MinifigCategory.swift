import Foundation
import SwiftData

@Model
final class MinifigCategory: Identifiable {
    @Attribute(.unique) var id: UUID
    var categoryID: String?
    var name: String
    var sortOrder: Int
    var minifigure: Minifigure?
    @Relationship(deleteRule: .nullify) var parent: MinifigCategory?
    @Relationship(deleteRule: .cascade, inverse: \MinifigCategory.parent) var children: [MinifigCategory]

    init(
        id: UUID = UUID(),
        categoryID: String? = nil,
        name: String,
        sortOrder: Int,
        minifigure: Minifigure? = nil,
        parent: MinifigCategory? = nil,
        children: [MinifigCategory] = []
    ) {
        self.id = id
        self.categoryID = categoryID
        self.name = name
        self.sortOrder = sortOrder
        self.minifigure = minifigure
        self.parent = parent
        self.children = children
    }
}

extension Array where Element == MinifigCategory {
    func sortedByOrder() -> [MinifigCategory] {
        sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.name < rhs.name
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }
}
