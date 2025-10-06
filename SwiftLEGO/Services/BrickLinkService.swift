import Foundation

struct BrickLinkSetPayload: Sendable {
    let setNumber: String
    let name: String
    let thumbnailURL: URL?
    let parts: [BrickLinkPartPayload]
}

struct BrickLinkPartPayload: Sendable {
    let partID: String
    let name: String
    let colorID: String
    let colorName: String
    let quantityNeeded: Int
    let imageURL: URL?
    let partURL: URL?
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
                partURL: part.partURL
            )
        }

        return BrickLinkSetPayload(
            setNumber: inventory.setNumber,
            name: inventory.name,
            thumbnailURL: inventory.thumbnailURL,
            parts: parts
        )
    }
}
