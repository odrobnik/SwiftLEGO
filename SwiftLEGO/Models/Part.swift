import Foundation
import SwiftData

@Model
final class Part: Identifiable {
    @Attribute(.unique) var id: UUID
    var partID: String
    var colorID: String
    var quantityNeeded: Int
    var quantityHave: Int
    var set: BrickSet?

    init(
        id: UUID = UUID(),
        partID: String,
        colorID: String,
        quantityNeeded: Int,
        quantityHave: Int = 0,
        set: BrickSet? = nil
    ) {
        self.id = id
        self.partID = partID
        self.colorID = colorID
        self.quantityNeeded = quantityNeeded
        self.quantityHave = quantityHave
        self.set = set
    }
}
