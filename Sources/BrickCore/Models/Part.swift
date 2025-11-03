import Foundation
import SwiftData

@Model
public final class Part: Identifiable {
    public enum InventorySection: String, Codable, CaseIterable, Sendable {
        case regular
        case counterpart
        case extra
        case alternate

        public var displayTitle: String {
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

        public var sortOrder: Int {
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

    @Attribute(.unique) public var id: UUID
    public var partID: String
    public var name: String
    public var colorID: String
    public var colorName: String
    public var quantityNeeded: Int
    public var quantityHave: Int
    public var imageURLString: String?
    public var partURLString: String?
    public var inventorySectionRawValue: String = InventorySection.regular.rawValue
    public var set: BrickSet?
    public var minifigure: Minifigure?
    @Relationship(deleteRule: .cascade, inverse: \Part.parentPart) public var subparts: [Part] = []
    @Relationship(deleteRule: .nullify) public var parentPart: Part?
    public var instanceNumber: Int = 1

    public init(
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
        set: BrickSet? = nil,
        minifigure: Minifigure? = nil,
        subparts: [Part] = [],
        parentPart: Part? = nil,
        instanceNumber: Int = 1
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
        self.minifigure = minifigure
        self.subparts = subparts
        self.parentPart = parentPart
        self.instanceNumber = instanceNumber
    }
}

public extension Part {
    var imageURL: URL? {
        guard let imageURLString else { return nil }
        return URL(string: imageURLString)
    }

    var highResolutionImageURL: URL? {
        guard let imageURL else { return nil }
        return Self.makeHighResolutionBrickLinkImageURL(from: imageURL)
    }

    var quickLookImageURL: URL? {
        highResolutionImageURL ?? imageURL
    }

    var partURL: URL? {
        guard let partURLString else { return nil }
        return URL(string: partURLString)
    }

    var inventorySection: InventorySection {
        get { InventorySection(rawValue: inventorySectionRawValue) ?? .regular }
        set { inventorySectionRawValue = newValue.rawValue }
    }

    private static func makeHighResolutionBrickLinkImageURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              host.contains("bricklink.com") else {
            return nil
        }

        let lowercasedPath = url.path.lowercased()
        if lowercasedPath.hasPrefix("/pl/") {
            return url
        }

        let filename = (url.path as NSString).lastPathComponent
        guard !filename.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.bricklink.com"
        components.path = "/PL/\(filename)"
        components.query = "0"

        return components.url
    }
}
