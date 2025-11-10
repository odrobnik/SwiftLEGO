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
    public var color: String?
    public var maxPrice: String
    public var minQuantity: Int
    public var remarks: String

    public init(
        itemType: ItemType,
        itemID: String,
        color: String? = nil,
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

extension WantedListItem {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.itemType = try container.decode(ItemType.self, forKey: .itemType)
        self.itemID = try container.decode(String.self, forKey: .itemID)
        self.color = try container.decodeIfPresent(String.self, forKey: .color)
        self.maxPrice = try container.decode(String.self, forKey: .maxPrice)
        self.minQuantity = try container.decode(Int.self, forKey: .minQuantity)
        self.remarks = try container.decode(String.self, forKey: .remarks)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemType, forKey: .itemType)
        try container.encode(itemID, forKey: .itemID)
        if let color {
            try container.encode(color, forKey: .color)
        }
        try container.encode(maxPrice, forKey: .maxPrice)
        try container.encode(minQuantity, forKey: .minQuantity)
        try container.encode(remarks, forKey: .remarks)
    }
}
