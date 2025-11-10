import Foundation

public struct WantedListInventory: Equatable, Codable {
    public var items: [WantedListItem]

    public init(items: [WantedListItem] = []) {
        self.items = items
    }

    enum CodingKeys: String, CodingKey {
        case items = "ITEM"
    }
}

public extension WantedListInventory {
    static let empty = WantedListInventory(items: [])
}

public struct WantedListItem: Equatable, Codable {
    public enum ItemType: String, Codable {
        case part = "P"
        case minifigure = "M"
    }

    public var itemType: ItemType
    public var itemID: String
    public var color: String
    public var maxPrice: String
    public var minQuantity: Int
    public var remarks: String

    public init(
        itemType: ItemType,
        itemID: String,
        color: String,
        maxPrice: String,
        minQuantity: Int,
        remarks: String
    ) {
        self.itemType = itemType
        self.itemID = itemID
        self.color = color
        self.maxPrice = maxPrice
        self.minQuantity = minQuantity
        self.remarks = remarks
    }

    enum CodingKeys: String, CodingKey {
        case itemType = "ITEMTYPE"
        case itemID = "ITEMID"
        case color = "COLOR"
        case maxPrice = "MAXPRICE"
        case minQuantity = "MINQTY"
        case remarks = "REMARKS"
    }
}
