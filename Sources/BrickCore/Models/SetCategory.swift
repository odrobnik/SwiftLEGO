import Foundation
import SwiftData

@Model
public final class SetCategory: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var categoryID: String?
    public var name: String
    public var sortOrder: Int
    public var set: BrickSet?
    @Relationship(deleteRule: .nullify) public var parent: SetCategory?
    @Relationship(deleteRule: .cascade, inverse: \SetCategory.parent) public var children: [SetCategory]

    public init(
        id: UUID = UUID(),
        categoryID: String? = nil,
        name: String,
        sortOrder: Int,
        set: BrickSet? = nil,
        parent: SetCategory? = nil,
        children: [SetCategory] = []
    ) {
        self.id = id
        self.categoryID = categoryID
        self.name = name
        self.sortOrder = sortOrder
        self.set = set
        self.parent = parent
        self.children = children
    }
}

public extension Array where Element == SetCategory {
    func sortedByOrder() -> [SetCategory] {
        sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.name < rhs.name
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }
}

public extension BrickSet {
    func normalizedCategoryPath(uncategorizedTitle: String) -> [String] {
        var names = categories
            .sortedByOrder()
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let first = names.first,
           first.compare("Catalog", options: .caseInsensitive) == .orderedSame {
            names.removeFirst()
        }

        while let first = names.first,
              first.compare("Sets", options: .caseInsensitive) == .orderedSame {
            names.removeFirst()
        }

        return names.isEmpty ? [uncategorizedTitle] : names
    }
}
