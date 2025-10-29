import Foundation
import SwiftData

@Model
public final class MinifigCategory: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var categoryID: String?
    public var name: String
    public var sortOrder: Int
    public var minifigure: Minifigure?
    @Relationship(deleteRule: .nullify) public var parent: MinifigCategory?
    @Relationship(deleteRule: .cascade, inverse: \MinifigCategory.parent) public var children: [MinifigCategory]

    public init(
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

public extension Array where Element == MinifigCategory {
    func sortedByOrder() -> [MinifigCategory] {
        sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.name < rhs.name
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }
}
