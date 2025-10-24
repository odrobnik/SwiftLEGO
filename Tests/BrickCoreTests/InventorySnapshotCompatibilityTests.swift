import Foundation
import SwiftData
import Testing
@testable import BrickCore

struct InventorySnapshotCompatibilityTests {
    @Test @MainActor
    func applyOldSnapshotAssignsQuantityToFirstInstance() {
        let context = makeSampleSet()

        let capeSnapshot = InventorySnapshot.SetSnapshot.PartSnapshot(
            partID: context.partOne.partID,
            colorID: context.partOne.colorID,
            quantityHave: 1,
            inventorySection: context.partOne.inventorySection.rawValue,
            instanceNumber: nil,
            subparts: nil
        )

        let minifigureSnapshot = InventorySnapshot.SetSnapshot.MinifigureSnapshot(
            identifier: context.figureOne.identifier,
            quantityHave: 2,
            instanceNumber: nil,
            parts: [capeSnapshot]
        )

        let setSnapshot = InventorySnapshot.SetSnapshot(
            id: context.set.id,
            setNumber: context.set.setNumber,
            name: context.set.name,
            thumbnailURLString: nil,
            parts: [],
            minifigures: [minifigureSnapshot]
        )

        let snapshot = InventorySnapshot(sets: [setSnapshot])
        let result = snapshot.apply(to: [context.list])

        #expect(result.updatedPartCount == 2, "Expected two updates (minifigure and part).")
        #expect(context.figureOne.quantityHave == 1, "Old snapshot should update the first instance.")
        #expect(context.figureTwo.quantityHave == 0, "Old snapshot should not modify additional instances.")
        #expect(context.partOne.quantityHave == 1, "Sub-part for the first instance should be updated.")
        #expect(context.partTwo.quantityHave == 0, "Sub-part for the second instance should remain untouched.")
    }

    @Test @MainActor
    func applyNewSnapshotAssignsQuantitiesPerInstance() {
        let context = makeSampleSet()

        let capeSnapshotOne = InventorySnapshot.SetSnapshot.PartSnapshot(
            partID: context.partOne.partID,
            colorID: context.partOne.colorID,
            quantityHave: 1,
            inventorySection: context.partOne.inventorySection.rawValue,
            instanceNumber: context.partOne.instanceNumber,
            subparts: nil
        )

        let capeSnapshotTwo = InventorySnapshot.SetSnapshot.PartSnapshot(
            partID: context.partTwo.partID,
            colorID: context.partTwo.colorID,
            quantityHave: 1,
            inventorySection: context.partTwo.inventorySection.rawValue,
            instanceNumber: context.partTwo.instanceNumber,
            subparts: nil
        )

        let minifigureSnapshotOne = InventorySnapshot.SetSnapshot.MinifigureSnapshot(
            identifier: context.figureOne.identifier,
            quantityHave: 1,
            instanceNumber: context.figureOne.instanceNumber,
            parts: [capeSnapshotOne]
        )

        let minifigureSnapshotTwo = InventorySnapshot.SetSnapshot.MinifigureSnapshot(
            identifier: context.figureTwo.identifier,
            quantityHave: 1,
            instanceNumber: context.figureTwo.instanceNumber,
            parts: [capeSnapshotTwo]
        )

        let setSnapshot = InventorySnapshot.SetSnapshot(
            id: context.set.id,
            setNumber: context.set.setNumber,
            name: context.set.name,
            thumbnailURLString: nil,
            parts: [],
            minifigures: [minifigureSnapshotOne, minifigureSnapshotTwo]
        )

        let snapshot = InventorySnapshot(sets: [setSnapshot])
        let result = snapshot.apply(to: [context.list])

        #expect(result.updatedPartCount == 4, "New snapshot should update both minifigures and both sub-parts.")
        #expect(context.figureOne.quantityHave == 1, "Instance 1 should reflect snapshot quantity.")
        #expect(context.figureTwo.quantityHave == 1, "Instance 2 should reflect snapshot quantity.")
        #expect(context.partOne.quantityHave == 1, "Sub-part for instance 1 should be updated.")
        #expect(context.partTwo.quantityHave == 1, "Sub-part for instance 2 should be updated.")
    }

    @Test
    func decodingRealWorldSnapshotFixture() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // InventorySnapshotCompatibilityTests.swift
            .deletingLastPathComponent() // BrickCoreTests

        let fixtureURL = testsDirectory
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("inventory-snapshot-2025-10-23_08-35-47.lego", isDirectory: false)

        #expect(FileManager.default.fileExists(atPath: fixtureURL.path), "Fixture file is missing at \(fixtureURL.path)")

        let data = try Data(contentsOf: fixtureURL)
        let decoder = JSONDecoder()
        let snapshot = try decoder.decode(InventorySnapshot.self, from: data)

        #expect(!snapshot.lists.isEmpty, "Snapshot should contain at least one list.")
        let allSets = snapshot.lists.flatMap { $0.sets }
        #expect(allSets.count > 0, "Snapshot should include sets.")

        if let firstList = snapshot.lists.first,
           let firstSet = firstList.sets.first,
           let firstMinifigure = firstSet.minifigures.first {
            #expect(firstMinifigure.identifier == "twn171", "Unexpected first minifigure identifier.")
            #expect(firstMinifigure.instanceNumber == nil, "Legacy snapshot minifigure should not have an instance number.")
        } else {
            Issue.record("Snapshot should contain at least one minifigure for validation.")
        }

        // Ensure we can re-encode without throwing, preserving compatibility.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        _ = try encoder.encode(snapshot)
    }

    private func makeSampleSet() -> (
        list: CollectionList,
        set: BrickSet,
        figureOne: Minifigure,
        figureTwo: Minifigure,
        partOne: Part,
        partTwo: Part
    ) {
        let list = CollectionList(name: "Test List")
        let set = BrickSet(setNumber: "75945-1", name: "Expecto Patronum")
        set.collection = list
        list.sets = [set]

        let figureOne = Minifigure(
            identifier: "hp155",
            name: "Dementor",
            quantityNeeded: 1,
            quantityHave: 0,
            set: set,
            instanceNumber: 1
        )

        let figureTwo = Minifigure(
            identifier: "hp155",
            name: "Dementor",
            quantityNeeded: 1,
            quantityHave: 0,
            set: set,
            instanceNumber: 2
        )

        let partOne = Part(
            partID: "86038",
            name: "Black Cape",
            colorID: "0",
            colorName: "Black",
            quantityNeeded: 1,
            quantityHave: 0,
            inventorySection: .regular,
            minifigure: figureOne,
            instanceNumber: 1
        )

        let partTwo = Part(
            partID: "86038",
            name: "Black Cape",
            colorID: "0",
            colorName: "Black",
            quantityNeeded: 1,
            quantityHave: 0,
            inventorySection: .regular,
            minifigure: figureTwo,
            instanceNumber: 1
        )

        figureOne.parts = [partOne]
        figureTwo.parts = [partTwo]
        set.minifigures = [figureOne, figureTwo]

        return (list, set, figureOne, figureTwo, partOne, partTwo)
    }

    @Test @MainActor
    func refreshSetPreservesQuantities() throws {
        let list = CollectionList(name: "Test List")
        let set = BrickSet(setNumber: "1234-1", name: "Sample Set")
        set.collection = list
        list.sets = [set]

        let topLevelPart = Part(
            partID: "3001",
            name: "Brick 2 x 4",
            colorID: "1",
            colorName: "White",
            quantityNeeded: 2,
            quantityHave: 1,
            inventorySection: .regular,
            set: set,
            instanceNumber: 1
        )

        let minifigure = Minifigure(
            identifier: "hp001",
            name: "Sample Figure",
            quantityNeeded: 1,
            quantityHave: 1,
            set: set,
            instanceNumber: 1
        )

        let minifigurePart = Part(
            partID: "86038",
            name: "Cape",
            colorID: "0",
            colorName: "Black",
            quantityNeeded: 1,
            quantityHave: 1,
            inventorySection: .regular,
            minifigure: minifigure,
            instanceNumber: 1
        )

        minifigure.parts = [minifigurePart]
        set.parts = [topLevelPart]
        set.minifigures = [minifigure]

        let partPayload = BrickLinkPartPayload(
            partID: "3001",
            name: "Brick 2 x 4",
            colorID: "1",
            colorName: "White",
            quantityNeeded: 2,
            instanceNumber: nil,
            imageURL: nil,
            partURL: nil,
            inventorySection: .regular,
            subparts: []
        )

        let minifigurePartPayload = BrickLinkPartPayload(
            partID: "86038",
            name: "Cape",
            colorID: "0",
            colorName: "Black",
            quantityNeeded: 1,
            instanceNumber: nil,
            imageURL: nil,
            partURL: nil,
            inventorySection: .regular,
            subparts: []
        )

        let minifigurePayload = BrickLinkMinifigurePayload(
            identifier: "hp001",
            name: "Sample Figure",
            quantityNeeded: 1,
            instanceNumber: nil,
            imageURL: nil,
            catalogURL: nil,
            inventoryURL: nil,
            categories: [],
            parts: [minifigurePartPayload]
        )

        let refreshPayload = BrickLinkSetPayload(
            setNumber: set.setNumber,
            name: set.name,
            thumbnailURL: nil,
            parts: [partPayload],
            categories: [],
            minifigures: [minifigurePayload]
        )

        let schema = Schema([
            CollectionList.self,
            BrickSet.self,
            Part.self,
            Minifigure.self,
            MinifigCategory.self
        ])

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)

        let context = ModelContext(container)
        context.insert(list)
        try context.save()

        let resolvedSnapshot = InventorySnapshot.make(from: [list])
        let previousSetSnapshot = resolvedSnapshot.sets.first { $0.setNumber == set.setNumber }

        SetImportUtilities.refreshSet(
            set: set,
            list: list,
            modelContext: context,
            payload: refreshPayload,
            previousSnapshot: previousSetSnapshot
        )

        let refreshedPart = set.parts.first
        let refreshedMinifigure = set.minifigures.first
        let refreshedMinifigurePart = refreshedMinifigure?.parts.first

        #expect(refreshedPart?.quantityHave == 1)
        #expect(refreshedMinifigure?.quantityHave == 1)
        #expect(refreshedMinifigurePart?.quantityHave == 1)
    }
}
