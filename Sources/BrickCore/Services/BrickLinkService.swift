import Foundation

public struct BrickLinkSetPayload: Sendable {
    public let setNumber: String
    public let name: String
    public let thumbnailURL: URL?
    public let parts: [BrickLinkPartPayload]
    public let categories: [SetCategoryPayload]
    public let minifigures: [BrickLinkMinifigurePayload]

    public init(
        setNumber: String,
        name: String,
        thumbnailURL: URL? = nil,
        parts: [BrickLinkPartPayload],
        categories: [SetCategoryPayload],
        minifigures: [BrickLinkMinifigurePayload]
    ) {
        self.setNumber = setNumber
        self.name = name
        self.thumbnailURL = thumbnailURL
        self.parts = parts
        self.categories = categories
        self.minifigures = minifigures
    }
}

public struct BrickLinkPartPayload: Sendable {
    public let partID: String
    public let name: String
    public let colorID: String
    public let colorName: String
    public let quantityNeeded: Int
    public let instanceNumber: Int?
    public let imageURL: URL?
    public let partURL: URL?
    public let inventorySection: Part.InventorySection
    public let subparts: [BrickLinkPartPayload]

    public init(
        partID: String,
        name: String,
        colorID: String,
        colorName: String,
        quantityNeeded: Int,
        instanceNumber: Int? = nil,
        imageURL: URL? = nil,
        partURL: URL? = nil,
        inventorySection: Part.InventorySection,
        subparts: [BrickLinkPartPayload] = []
    ) {
        self.partID = partID
        self.name = name
        self.colorID = colorID
        self.colorName = colorName
        self.quantityNeeded = quantityNeeded
        self.instanceNumber = instanceNumber
        self.imageURL = imageURL
        self.partURL = partURL
        self.inventorySection = inventorySection
        self.subparts = subparts
    }
}

public struct SetCategoryPayload: Sendable, Equatable {
    public let id: String?
    public let name: String

    public init(id: String? = nil, name: String) {
        self.id = id
        self.name = name
    }
}

public struct BrickLinkMinifigurePayload: Sendable {
    public let identifier: String
    public let name: String
    public let quantityNeeded: Int
    public let instanceNumber: Int?
    public let imageURL: URL?
    public let catalogURL: URL?
    public let inventoryURL: URL?
    public let categories: [MinifigCategoryPayload]
    public let parts: [BrickLinkPartPayload]

    public init(
        identifier: String,
        name: String,
        quantityNeeded: Int,
        instanceNumber: Int? = nil,
        imageURL: URL? = nil,
        catalogURL: URL? = nil,
        inventoryURL: URL? = nil,
        categories: [MinifigCategoryPayload] = [],
        parts: [BrickLinkPartPayload] = []
    ) {
        self.identifier = identifier
        self.name = name
        self.quantityNeeded = quantityNeeded
        self.instanceNumber = instanceNumber
        self.imageURL = imageURL
        self.catalogURL = catalogURL
        self.inventoryURL = inventoryURL
        self.categories = categories
        self.parts = parts
    }
}

public struct MinifigCategoryPayload: Sendable, Equatable {
    public let id: String?
    public let name: String

    public init(id: String?, name: String) {
        self.id = id
        self.name = name
    }
}

public actor BrickLinkService {
    private let inventoryService: BrickLinkInventoryService

    public init(inventoryService: BrickLinkInventoryService = BrickLinkInventoryService()) {
        self.inventoryService = inventoryService
    }

    public func fetchSetDetails(for setNumber: String) async throws -> BrickLinkSetPayload {
        let inventory = try await inventoryService.fetchInventory(for: setNumber)

        let parts = inventory.parts.map { part in
            makePartPayload(from: part)
        }

        let minifigures = inventory.minifigures.map { minifigure in
            BrickLinkMinifigurePayload(
                identifier: minifigure.identifier,
                name: minifigure.name,
                quantityNeeded: minifigure.quantity,
                instanceNumber: nil,
                imageURL: minifigure.imageURL,
                catalogURL: minifigure.catalogURL,
                inventoryURL: minifigure.inventoryURL,
                categories: minifigure.categories.map { MinifigCategoryPayload(id: $0.id, name: $0.name) },
                parts: minifigure.parts.map { part in
                    makePartPayload(from: part)
                }
            )
        }

        return BrickLinkSetPayload(
            setNumber: inventory.setNumber,
            name: inventory.name,
            thumbnailURL: inventory.thumbnailURL,
            parts: parts,
            categories: inventory.categories.map { SetCategoryPayload(id: $0.id, name: $0.name) },
            minifigures: minifigures
        )
    }

    private func makePartPayload(from part: BrickLinkPart) -> BrickLinkPartPayload {
        BrickLinkPartPayload(
            partID: part.partID,
            name: part.name,
            colorID: part.colorID,
            colorName: part.colorName,
            quantityNeeded: part.quantity,
            instanceNumber: nil,
            imageURL: part.imageURL,
            partURL: part.partURL,
            inventorySection: Part.InventorySection(brickLinkSection: part.section),
            subparts: part.subparts.map { makePartPayload(from: $0) }
        )
    }
}

private extension Part.InventorySection {
    init(brickLinkSection: BrickLinkPartSection) {
        switch brickLinkSection {
        case .regular:
            self = .regular
        case .counterpart:
            self = .counterpart
        case .extra:
            self = .extra
        case .alternate:
            self = .alternate
        }
    }
}
