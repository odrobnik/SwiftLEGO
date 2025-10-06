import Foundation
import SwiftData

@Model
final class Part: Identifiable {
    @Attribute(.unique) var id: UUID
    var partID: String
    var name: String
    var colorID: String
    var colorName: String
    var quantityNeeded: Int
    var quantityHave: Int
    var imageURLString: String?
    var partURLString: String?
    var set: BrickSet?

    init(
        id: UUID = UUID(),
        partID: String,
        name: String,
        colorID: String,
        colorName: String,
        quantityNeeded: Int,
        quantityHave: Int = 0,
        imageURLString: String? = nil,
        partURLString: String? = nil,
        set: BrickSet? = nil
    ) {
        self.id = id
        self.partID = partID
        self.name = name
        self.colorID = colorID
        self.colorName = colorName
        self.quantityNeeded = quantityNeeded
        self.quantityHave = quantityHave
        self.imageURLString = imageURLString
        self.partURLString = partURLString
        self.set = set
    }
}

extension Part {
    var imageURL: URL? {
        guard let imageURLString else { return nil }
        return URL(string: imageURLString)
    }

    var partURL: URL? {
        guard let partURLString else { return nil }
        return URL(string: partURLString)
    }
}
