import Foundation
import SwiftData
#if canImport(BrickCore)
import BrickCore
#endif

struct OrderPartRoute: Hashable {
    let orderPart: OrderPart
    let searchQuery: String?

    static func == (lhs: OrderPartRoute, rhs: OrderPartRoute) -> Bool {
        lhs.orderPart.persistentModelID == rhs.orderPart.persistentModelID &&
        lhs.searchQuery == rhs.searchQuery
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(orderPart.persistentModelID)
        hasher.combine(searchQuery)
    }
}
