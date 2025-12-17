import Foundation
import SwiftData

@Model
public final class OrderPart: Identifiable {
    public enum ItemType: String, Codable, CaseIterable, Sendable {
        case part
        case minifigure
    }

    @Attribute(.unique) public var id: UUID
    public var itemTypeRawValue: String = ItemType.part.rawValue
    public var partID: String
    public var name: String
    public var colorID: String
    public var colorName: String
    public var quantity: Int
    public var imageURLString: String?
    public var order: BrickOrder?

    public init(
        id: UUID = UUID(),
        itemType: ItemType = .part,
        partID: String,
        name: String,
        colorID: String,
        colorName: String,
        quantity: Int,
        imageURLString: String? = nil,
        order: BrickOrder? = nil
    ) {
        self.id = id
        self.itemTypeRawValue = itemType.rawValue
        self.partID = partID
        self.name = name
        self.colorID = colorID
        self.colorName = colorName
        self.quantity = quantity
        self.imageURLString = imageURLString
        self.order = order
    }
}

public extension OrderPart {
    var itemType: ItemType {
        get { ItemType(rawValue: itemTypeRawValue) ?? .part }
        set { itemTypeRawValue = newValue.rawValue }
    }

    var imageURL: URL? {
        guard let imageURLString else { return nil }
        return URL(string: imageURLString)
    }
}
