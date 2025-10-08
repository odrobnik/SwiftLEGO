import Foundation
import SwiftData

@Model
final class Part: Identifiable {
    enum InventorySection: String, Codable, CaseIterable, Sendable {
        case regular
        case counterpart
        case extra
        case alternate

        var displayTitle: String {
            switch self {
            case .regular:
                return "Regular Items"
            case .counterpart:
                return "Counterpart Items"
            case .extra:
                return "Extra Items"
            case .alternate:
                return "Alternate Items"
            }
        }

        var sortOrder: Int {
            switch self {
            case .regular:
                return 0
            case .counterpart:
                return 1
            case .extra:
                return 2
            case .alternate:
                return 3
            }
        }
    }

    @Attribute(.unique) var id: UUID
    var partID: String
    var name: String
    var colorID: String
    var colorName: String
    var quantityNeeded: Int
    var quantityHave: Int
    var imageURLString: String?
    var partURLString: String?
    var inventorySectionRawValue: String = InventorySection.regular.rawValue
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
        inventorySection: InventorySection = .regular,
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
        self.inventorySectionRawValue = inventorySection.rawValue
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

    var inventorySection: InventorySection {
        get { InventorySection(rawValue: inventorySectionRawValue) ?? .regular }
        set { inventorySectionRawValue = newValue.rawValue }
    }
}
