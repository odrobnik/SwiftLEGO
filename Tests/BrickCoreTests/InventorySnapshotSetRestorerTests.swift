import Foundation
import Testing
@testable import BrickCore

@MainActor
struct InventorySnapshotSetRestorerTests {
    @Test
    func importingSetAppliesSnapshotQuantities() async throws {
        let context = try makeInMemoryModelContext()
        let list = CollectionList(name: "Restored")
        context.insert(list)

        let partSnapshot = InventorySnapshot.SetSnapshot.PartSnapshot(
            partID: "3001",
            colorID: "5",
            quantityHave: 2,
            inventorySection: Part.InventorySection.regular.rawValue,
            instanceNumber: nil,
            subparts: nil
        )

        let setSnapshot = InventorySnapshot.SetSnapshot(
            setNumber: "10220-1",
            name: "Volkswagen T1 Camper Van",
            thumbnailURLString: nil,
            parts: [partSnapshot]
        )

        let partPayload = BrickLinkPartPayload(
            partID: "3001",
            name: "Brick 2 x 4",
            colorID: "5",
            colorName: "Red",
            quantityNeeded: 4,
            inventorySection: .regular
        )

        let payload = BrickLinkSetPayload(
            setNumber: "10220-1",
            name: "Volkswagen T1 Camper Van",
            thumbnailURL: URL(string: "https://example.com/thumb.png"),
            parts: [partPayload],
            categories: [],
            minifigures: []
        )

        let service = MockBrickLinkService()
        await service.setPayload(payload, for: "10220-1")

        let provider = InventoryImportSetProvider(modelContext: context, service: service)
        let restorer = InventorySnapshotSetRestorer(modelContext: context, setProvider: provider)

        let importedSet = try await restorer.importSet(setSnapshot, into: list)
        #expect(list.sets.count == 1)
        #expect(importedSet.setNumber == "10220-1")
        #expect(importedSet.parts.count == 1)
        guard let part = importedSet.parts.first else {
            Issue.record("Expected imported set to include a part")
            return
        }

        #expect(part.quantityHave == 2, "Snapshot quantities should be applied to the new set.")
    }
}
