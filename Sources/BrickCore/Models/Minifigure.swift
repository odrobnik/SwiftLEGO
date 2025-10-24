import Foundation
import SwiftData

@Model
final class Minifigure: Identifiable {
    @Attribute(.unique) var id: UUID
    var identifier: String
    var name: String
    var quantityNeeded: Int
    var quantityHave: Int
    var imageURLString: String?
    var catalogURLString: String?
    var inventoryURLString: String?
    var set: BrickSet?
    @Relationship(deleteRule: .cascade, inverse: \Part.minifigure) var parts: [Part]
    @Relationship(deleteRule: .cascade, inverse: \MinifigCategory.minifigure) var categories: [MinifigCategory]
    var instanceNumber: Int = 1

    init(
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

extension Minifigure {
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

extension Minifigure {
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

extension Minifigure {
    var displayIdentifierWithInstance: String {
        "\(identifier)#\(instanceNumber)"
    }

    var displayNameWithInstance: String {
        instanceNumber > 1 ? "\(name) #\(instanceNumber)" : name
    }
}
