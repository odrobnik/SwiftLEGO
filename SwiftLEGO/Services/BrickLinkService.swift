import Foundation

struct BrickLinkSetPayload: Sendable {
    let setNumber: String
    let name: String
    let thumbnailURL: URL?
    let parts: [BrickLinkPartPayload]
    let categories: [SetCategoryPayload]
    let minifigures: [BrickLinkMinifigurePayload]
}

struct BrickLinkPartPayload: Sendable {
    let partID: String
    let name: String
    let colorID: String
    let colorName: String
    let quantityNeeded: Int
    let imageURL: URL?
    let partURL: URL?
    let inventorySection: Part.InventorySection
}

struct SetCategoryPayload: Sendable, Equatable {
    let id: String?
    let name: String
}

struct BrickLinkMinifigurePayload: Sendable {
    let identifier: String
    let name: String
    let quantityNeeded: Int
    let imageURL: URL?
    let catalogURL: URL?
    let inventoryURL: URL?
    let categories: [MinifigCategoryPayload]
    let parts: [BrickLinkPartPayload]
}

struct MinifigCategoryPayload: Sendable, Equatable {
    let id: String?
    let name: String
}

actor BrickLinkService {
    private let inventoryService = BrickLinkInventoryService()

    func fetchSetDetails(for setNumber: String) async throws -> BrickLinkSetPayload {
        let inventory = try await inventoryService.fetchInventory(for: setNumber)

        let parts = inventory.parts.map { part in
            BrickLinkPartPayload(
                partID: part.partID,
                name: part.name,
                colorID: part.colorID,
                colorName: part.colorName,
                quantityNeeded: part.quantity,
                imageURL: part.imageURL,
                partURL: part.partURL,
                inventorySection: Part.InventorySection(brickLinkSection: part.section)
            )
        }

        let minifigures = inventory.minifigures.map { minifigure in
            BrickLinkMinifigurePayload(
                identifier: minifigure.identifier,
                name: minifigure.name,
                quantityNeeded: minifigure.quantity,
                imageURL: minifigure.imageURL,
                catalogURL: minifigure.catalogURL,
                inventoryURL: minifigure.inventoryURL,
                categories: minifigure.categories.map { MinifigCategoryPayload(id: $0.id, name: $0.name) },
                parts: minifigure.parts.map { part in
                    BrickLinkPartPayload(
                        partID: part.partID,
                        name: part.name,
                        colorID: part.colorID,
                        colorName: part.colorName,
                        quantityNeeded: part.quantity,
                        imageURL: part.imageURL,
                        partURL: part.partURL,
                        inventorySection: Part.InventorySection(brickLinkSection: part.section)
                    )
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
