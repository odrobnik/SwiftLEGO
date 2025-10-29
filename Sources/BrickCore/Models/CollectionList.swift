import Foundation
import SwiftData

@Model
public final class CollectionList: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var name: String
    @Relationship(deleteRule: .cascade, inverse: \BrickSet.collection) public var sets: [BrickSet]

    public init(id: UUID = UUID(), name: String, sets: [BrickSet] = []) {
        self.id = id
        self.name = name
        self.sets = sets
    }
}
