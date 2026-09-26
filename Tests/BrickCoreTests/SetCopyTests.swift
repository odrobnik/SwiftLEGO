import Foundation
import SwiftData
import Testing
@testable import BrickCore

/// A set that is already in the collection is copied instead of being fetched
/// from BrickLink again, so the copy has to match the original exactly.
@MainActor
struct SetCopyTests {
    /// As BrickLink lists them: a subpart's quantity is per parent part.
    private static let payload = BrickLinkSetPayload(
        setNumber: "75946-1",
        name: "Hungarian Horntail Triwizard Challenge",
        parts: [
            BrickLinkPartPayload(
                partID: "36752",
                name: "Dragon Wing Assembly",
                colorID: "85",
                colorName: "Dark Bluish Gray",
                quantityNeeded: 2,
                inventorySection: .regular,
                subparts: [
                    BrickLinkPartPayload(
                        partID: "36752sprue",
                        name: "Dragon Wing Feather Sprue",
                        colorID: "85",
                        colorName: "Dark Bluish Gray",
                        quantityNeeded: 3,
                        inventorySection: .regular,
                        subparts: [
                            BrickLinkPartPayload(
                                partID: "36752a",
                                name: "Dragon Wing Feather",
                                colorID: "85",
                                colorName: "Dark Bluish Gray",
                                quantityNeeded: 2,
                                inventorySection: .regular
                            )
                        ]
                    )
                ]
            )
        ],
        categories: [],
        minifigures: [
            BrickLinkMinifigurePayload(
                identifier: "hp180",
                name: "Harry Potter",
                quantityNeeded: 1,
                parts: [
                    BrickLinkPartPayload(
                        partID: "93082",
                        name: "Accessories Multipack",
                        colorID: "42",
                        colorName: "Medium Blue",
                        quantityNeeded: 2,
                        inventorySection: .regular,
                        subparts: [
                            BrickLinkPartPayload(
                                partID: "93082g",
                                name: "Hair Brush",
                                colorID: "",
                                colorName: "",
                                quantityNeeded: 3,
                                inventorySection: .regular
                            )
                        ]
                    )
                ]
            )
        ]
    )

    @Test
    func copyingASetKeepsItsSubpartQuantities() throws {
        let context = try makeInMemoryModelContext()
        let list = CollectionList(name: "Hogwarts")
        context.insert(list)

        let original = persistOriginal(in: list, context: context)

        // Stored subpart quantities are totals: the per-parent count times the parent's.
        #expect(neededQuantities(in: original) == [
            "36752": 2,
            "36752/36752sprue": 6,
            "36752/36752sprue/36752a": 12,
            "hp180#1/93082": 2,
            "hp180#1/93082/93082g": 6
        ])

        // How AddSetView and BulkAddSetsView copy a set already in the collection.
        let copy = SetImportUtilities.persistSet(
            list: list,
            modelContext: context,
            setNumber: original.setNumber,
            defaultName: original.name,
            customName: nil,
            thumbnailURLString: original.thumbnailURLString,
            parts: SetImportUtilities.partPayloads(from: original.parts),
            categories: SetImportUtilities.categoryPayloads(from: original.categories),
            minifigures: SetImportUtilities.minifigurePayloads(from: original.minifigures)
        )

        #expect(neededQuantities(in: copy) == neededQuantities(in: original))
    }

    @Test
    func restoringASnapshotFromTheSetInTheCollectionKeepsItsSubpartQuantities() async throws {
        let context = try makeInMemoryModelContext()
        let list = CollectionList(name: "Hogwarts")
        context.insert(list)

        let original = persistOriginal(in: list, context: context)
        let originalParts = partsByPath(in: original)
        try #require(originalParts["36752/36752sprue"]).quantityHave = 4
        try #require(originalParts["36752/36752sprue/36752a"]).quantityHave = 8
        try context.save()

        // Exported to a file and read back, as the app does.
        let file = try JSONEncoder().encode(InventorySnapshot.make(from: [list]))
        let exported = try JSONDecoder().decode(InventorySnapshot.self, from: file)
        let setSnapshot = try #require(exported.lists.first?.sets.first)

        // Without a payload a BrickLink fetch fails, so the restorer has to copy `original`.
        let service = MockBrickLinkService()
        let provider = InventoryImportSetProvider(modelContext: context, service: service)
        let restorer = InventorySnapshotSetRestorer(modelContext: context, setProvider: provider)

        let restoredList = CollectionList(name: "Restored")
        context.insert(restoredList)
        let restored = try await restorer.importSet(setSnapshot, into: restoredList)

        #expect(await service.recordedRequests().isEmpty)
        #expect(neededQuantities(in: restored) == neededQuantities(in: original))
        #expect(quantitiesHave(in: restored) == quantitiesHave(in: original))
    }

    // MARK: - Helpers

    private func persistOriginal(in list: CollectionList, context: ModelContext) -> BrickSet {
        SetImportUtilities.persistSet(
            list: list,
            modelContext: context,
            setNumber: Self.payload.setNumber,
            defaultName: Self.payload.name,
            customName: nil,
            thumbnailURLString: nil,
            parts: Self.payload.parts,
            categories: Self.payload.categories,
            minifigures: Self.payload.minifigures
        )
    }

    /// Every part of `set`, nested ones included, keyed by its path of part IDs;
    /// a minifigure's parts sit under "identifier#instance".
    private func partsByPath(in set: BrickSet) -> [String: Part] {
        var partsByPath: [String: Part] = [:]

        func collect(_ parts: [Part], under prefix: String) {
            for part in parts {
                let path = prefix + part.partID
                partsByPath[path] = part
                collect(part.subparts, under: path + "/")
            }
        }

        collect(set.parts, under: "")
        for minifigure in set.minifigures {
            collect(minifigure.parts, under: "\(minifigure.identifier)#\(minifigure.instanceNumber)/")
        }

        return partsByPath
    }

    private func neededQuantities(in set: BrickSet) -> [String: Int] {
        partsByPath(in: set).mapValues(\.quantityNeeded)
    }

    private func quantitiesHave(in set: BrickSet) -> [String: Int] {
        partsByPath(in: set).mapValues(\.quantityHave)
    }
}
