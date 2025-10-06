import Foundation
import SwiftData

@Model
final class CollectionList: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    @Relationship(deleteRule: .cascade, inverse: \BrickSet.collection) var sets: [BrickSet]

    init(id: UUID = UUID(), name: String, sets: [BrickSet] = []) {
        self.id = id
        self.name = name
        self.sets = sets
    }
}
