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

    public enum Condition: String, Codable {
        case new = "N"
    }

    public enum NotificationState: String, Codable {
        case enabled = "Y"
        case disabled = "N"
    }

    public var itemType: ItemType
    public var itemID: String
    public var color: String
    public var maxPrice: String
    public var minQuantity: Int
    public var condition: Condition
    public var remarks: String
    public var notify: NotificationState

    public init(
        itemType: ItemType,
        itemID: String,
        color: String,
        maxPrice: String,
        minQuantity: Int,
        condition: Condition,
        remarks: String,
        notify: NotificationState
    ) {
        self.itemType = itemType
        self.itemID = itemID
        self.color = color
        self.maxPrice = maxPrice
        self.minQuantity = minQuantity
        self.condition = condition
        self.remarks = remarks
        self.notify = notify
    }

    enum CodingKeys: String, CodingKey {
        case itemType = "ITEMTYPE"
        case itemID = "ITEMID"
        case color = "COLOR"
        case maxPrice = "MAXPRICE"
        case minQuantity = "MINQTY"
        case condition = "CONDITION"
        case remarks = "REMARKS"
        case notify = "NOTIFY"
    }
}
