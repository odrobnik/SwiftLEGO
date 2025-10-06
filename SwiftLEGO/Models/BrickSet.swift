import Foundation
import SwiftData

@Model
final class BrickSet: Identifiable {
    @Attribute(.unique) var id: UUID
    var setNumber: String
    var name: String
    var thumbnailURLString: String?
    @Relationship(deleteRule: .cascade, inverse: \Part.set) var parts: [Part]
    var collection: CollectionList?

    init(
        id: UUID = UUID(),
        setNumber: String,
        name: String,
        thumbnailURLString: String? = nil,
        parts: [Part] = [],
        collection: CollectionList? = nil
    ) {
        self.id = id
        self.setNumber = setNumber
        self.name = name
        self.thumbnailURLString = thumbnailURLString
        self.parts = parts
        self.collection = collection
    }
}

extension BrickSet {
    var thumbnailURL: URL? {
        guard let thumbnailURLString else { return nil }
        return URL(string: thumbnailURLString)
    }
}
