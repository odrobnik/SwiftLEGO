import Foundation
import SwiftData

@Model
public final class Minifigure: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var identifier: String
    public var name: String
    public var quantityNeeded: Int
    public var quantityHave: Int
    public var imageURLString: String?
    public var catalogURLString: String?
    public var inventoryURLString: String?
    public var set: BrickSet?
    @Relationship(deleteRule: .cascade, inverse: \Part.minifigure) public var parts: [Part]
    @Relationship(deleteRule: .cascade, inverse: \MinifigCategory.minifigure) public var categories: [MinifigCategory]
    public var instanceNumber: Int = 1

    public init(
        id: UUID = UUID(),
        identifier: String,
        name: String,
        quantityNeeded: Int,
        quantityHave: Int = 0,
        imageURLString: String? = nil,
        catalogURLString: String? = nil,
        inventoryURLString: String? = nil,
        set: BrickSet? = nil,
        parts: [Part] = [],
        categories: [MinifigCategory] = [],
        instanceNumber: Int = 1
    ) {
        self.id = id
        self.identifier = identifier
        self.name = name
        self.quantityNeeded = quantityNeeded
        self.quantityHave = quantityHave
        self.imageURLString = imageURLString
        self.catalogURLString = catalogURLString
        self.inventoryURLString = inventoryURLString
        self.set = set
        self.parts = parts
        self.categories = categories
        self.instanceNumber = instanceNumber
    }
}

public extension Minifigure {
    var imageURL: URL? {
        guard let imageURLString else { return nil }
        return URL(string: imageURLString)
    }

    var catalogURL: URL? {
        guard let catalogURLString else { return nil }
        return URL(string: catalogURLString)
    }

    var inventoryURL: URL? {
        guard let inventoryURLString else { return nil }
        return URL(string: inventoryURLString)
    }
}

public extension Minifigure {
    func normalizedCategoryPath(uncategorizedTitle: String) -> [String] {
        var names = categories
            .sortedByOrder()
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let first = names.first,
           first.compare("Catalog", options: .caseInsensitive) == .orderedSame {
            names.removeFirst()
        }

        return names.isEmpty ? [uncategorizedTitle] : names
    }
}

public extension Minifigure {
    private var siblingInstanceCount: Int {
        guard let set else { return 1 }
        return set.minifigures.filter { $0.identifier.caseInsensitiveCompare(identifier) == .orderedSame }.count
    }

    var shouldDisplayInstanceSuffix: Bool {
        siblingInstanceCount > 1
    }

    func displayIdentifier(includeInstanceSuffix: Bool? = nil) -> String {
        let include = includeInstanceSuffix ?? shouldDisplayInstanceSuffix
        return include ? "\(identifier)#\(instanceNumber)" : identifier
    }

    func displayName(includeInstanceSuffix: Bool? = nil) -> String {
        let include = includeInstanceSuffix ?? shouldDisplayInstanceSuffix
        return include ? "\(name) #\(instanceNumber)" : name
    }
}

extension Minifigure: Hashable {
    public static func == (lhs: Minifigure, rhs: Minifigure) -> Bool {
        lhs.persistentModelID == rhs.persistentModelID
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(persistentModelID)
    }
}
