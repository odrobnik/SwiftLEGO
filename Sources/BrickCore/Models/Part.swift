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
    public var fullImageURLString: String?
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
        fullImageURLString: String? = nil,
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
        self.fullImageURLString = fullImageURLString
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

    var fullImageURL: URL? {
        guard let fullImageURLString else { return nil }
        return URL(string: fullImageURLString)
    }

    var thumbnailImageURL: URL? {
        if let imageURL {
            let path = imageURL.path.lowercased()
            if !path.contains("no_image") {
                return imageURL
            }
        }

        return Self.makeColorSpecificThumbnailURL(partID: partID, colorID: colorID)
    }

    var highResolutionImageURL: URL? {
        if let fullImageURL, !fullImageURL.path.lowercased().contains("no_image") {
            if fullImageURL.path.lowercased().contains("/pl/"),
               let colorSpecific = Self.makeColorSpecificImageURL(partID: partID, colorID: colorID) {
                return colorSpecific
            }
            // Older imports stored the 80 x 60 legacy thumbnail as the full image of
            // parts without a color, such as sticker sheets.
            return Self.mainImageURL(forLegacyImage: fullImageURL) ?? fullImageURL
        }

        if let colorSpecific = Self.makeColorSpecificImageURL(partID: partID, colorID: colorID) {
            return colorSpecific
        }

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

    /// BrickLink's legacy part image, `img.bricklink.com/P/<color>/<item>.jpg`, is an
    /// 80 x 60 thumbnail. The main image is filed under the same color, `0` for items
    /// without one: `ItemImage/PN/<color>/<item>.png`.
    internal static func mainImageURL(forLegacyImage url: URL) -> URL? {
        let pathComponents = url.pathComponents
        guard url.host?.lowercased() == "img.bricklink.com",
              pathComponents.count == 4,
              pathComponents[1].uppercased() == "P" else {
            return nil
        }

        let colorID = pathComponents[2]
        let itemNumber = (pathComponents[3] as NSString).deletingPathExtension
        guard !colorID.isEmpty, !itemNumber.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "img.bricklink.com"
        components.path = "/ItemImage/PN/\(colorID)/\(itemNumber).png"
        return components.url
    }

    internal static func makeColorSpecificImageURL(partID: String, colorID: String) -> URL? {
        let trimmedPartID = partID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedColorID = colorID.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedColorID = trimmedColorID == "0" ? "" : trimmedColorID
        guard !trimmedPartID.isEmpty, !sanitizedColorID.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "img.bricklink.com"
        components.path = "/ItemImage/PN/\(sanitizedColorID)/\(trimmedPartID).png"
        return components.url
    }

    internal static func makeColorSpecificThumbnailURL(partID: String, colorID: String) -> URL? {
        let trimmedPartID = partID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedColorID = colorID.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedColorID = trimmedColorID == "0" ? "" : trimmedColorID
        guard !trimmedPartID.isEmpty, !sanitizedColorID.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "img.bricklink.com"
        components.path = "/ItemImage/PT/\(sanitizedColorID)/\(trimmedPartID).t1.png"
        return components.url
    }
}

extension Part {
    /// Moves this part to the number BrickLink renumbered it to, with the image
    /// and catalog URLs that belong to the new number.
    func adoptItemNumber(_ itemNumber: String) {
        let previousNumber = partID
        partID = itemNumber

        if let thumbnail = Self.makeColorSpecificThumbnailURL(partID: itemNumber, colorID: colorID) {
            imageURLString = thumbnail.absoluteString
        }

        if let fullImage = Self.makeColorSpecificImageURL(partID: itemNumber, colorID: colorID) {
            fullImageURLString = fullImage.absoluteString
        }

        // `catalogitem.page?P=14769pb328&idColor=157` names the item in its `P` query item.
        if let partURLString,
           var components = URLComponents(string: partURLString),
           let index = components.queryItems?.firstIndex(where: { $0.name == "P" && $0.value == previousNumber }) {
            components.queryItems?[index].value = itemNumber
            self.partURLString = components.string ?? partURLString
        }
    }
}
