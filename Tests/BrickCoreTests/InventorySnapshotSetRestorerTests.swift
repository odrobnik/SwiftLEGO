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

    @Test
    func completingParentPartCompletesSubparts() async throws {
        let context = try makeInMemoryModelContext()
        let list = CollectionList(name: "Forbidden Forest")
        context.insert(list)

        let wingFeatherPayload = BrickLinkPartPayload(
            partID: "36752a",
            name: "Dragon Wing Feathers",
            colorID: "85",
            colorName: "Dark Bluish Gray",
            quantityNeeded: 2,
            inventorySection: .regular
        )

        let wingAssemblyPayload = BrickLinkPartPayload(
            partID: "36752",
            name: "Dragon Wing Assembly",
            colorID: "85",
            colorName: "Dark Bluish Gray",
            quantityNeeded: 1,
            inventorySection: .regular,
            subparts: [wingFeatherPayload]
        )

        let payload = BrickLinkSetPayload(
            setNumber: "75946-1",
            name: "Hungarian Horntail Triwizard Challenge",
            thumbnailURL: nil,
            parts: [wingAssemblyPayload],
            categories: [],
            minifigures: []
        )

        let parentSnapshot = InventorySnapshot.SetSnapshot.PartSnapshot(
            partID: "36752",
            colorID: "85",
            quantityHave: 1,
            inventorySection: Part.InventorySection.regular.rawValue,
            instanceNumber: nil,
            subparts: nil
        )

        let setSnapshot = InventorySnapshot.SetSnapshot(
            setNumber: "75946-1",
            name: "Hungarian Horntail Triwizard Challenge",
            thumbnailURLString: nil,
            parts: [parentSnapshot]
        )

        let service = MockBrickLinkService()
        await service.setPayload(payload, for: "75946-1")

        let provider = InventoryImportSetProvider(modelContext: context, service: service)
        let restorer = InventorySnapshotSetRestorer(modelContext: context, setProvider: provider)

        let importedSet = try await restorer.importSet(setSnapshot, into: list)

        guard let parentPart = importedSet.parts.first(where: { $0.partID == "36752" }) else {
            Issue.record("Expected to find part 36752 in imported set.")
            return
        }

        guard let childPart = parentPart.subparts.first(where: { $0.partID == "36752a" }) else {
            Issue.record("Expected to find sub-part 36752a beneath part 36752.")
            return
        }

        #expect(parentPart.quantityHave == parentPart.quantityNeeded)
        #expect(childPart.quantityHave == childPart.quantityNeeded, "Completing a parent should complete all of its sub-parts.")
    }
}
