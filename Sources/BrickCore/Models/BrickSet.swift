import Foundation
import SwiftData

@Model
public final class BrickSet: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var setNumber: String
    public var name: String
    public var thumbnailURLString: String?
    @Relationship(deleteRule: .cascade, inverse: \Part.set) public var parts: [Part]
    public var collection: CollectionList?
    @Relationship(deleteRule: .cascade, inverse: \SetCategory.set) public var categories: [SetCategory]
    @Relationship(deleteRule: .cascade, inverse: \Minifigure.set) public var minifigures: [Minifigure]

    public init(
        id: UUID = UUID(),
        setNumber: String,
        name: String,
        thumbnailURLString: String? = nil,
        parts: [Part] = [],
        collection: CollectionList? = nil,
        categories: [SetCategory] = [],
        minifigures: [Minifigure] = []
    ) {
        self.id = id
        self.setNumber = setNumber
        self.name = name
        self.thumbnailURLString = thumbnailURLString
        self.parts = parts
        self.collection = collection
        self.categories = categories
        self.minifigures = minifigures
    }
}

public extension BrickSet {
    var thumbnailURL: URL? {
        guard let thumbnailURLString else { return nil }
        return URL(string: thumbnailURLString)
    }
}
