import Foundation
import SwiftData

@Model
public final class BrickOrder: Identifiable {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var orderNumber: String?
    public var sourceFilename: String?
    public var importedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \OrderPart.order) public var parts: [OrderPart]

    public init(
        id: UUID = UUID(),
        name: String,
        orderNumber: String? = nil,
        sourceFilename: String? = nil,
        importedAt: Date = Date(),
        parts: [OrderPart] = []
    ) {
        self.id = id
        self.name = name
        self.orderNumber = orderNumber
        self.sourceFilename = sourceFilename
        self.importedAt = importedAt
        self.parts = parts
    }
}

public extension BrickOrder {
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if let orderNumber, !orderNumber.isEmpty {
            return "Order #\(orderNumber)"
        }
        return "Order"
    }
}
