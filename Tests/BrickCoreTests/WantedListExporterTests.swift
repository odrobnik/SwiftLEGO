import Testing
@testable import BrickCore

@Suite
struct WantedListExporterTests {
    @Test @MainActor
    func aggregatesMissingPartsAcrossLists() throws {
        let listA = CollectionList(name: "List A")
        let listB = CollectionList(name: "List B")

        let setA = BrickSet(setNumber: "1234-1", name: "Alpha")
        let setB = BrickSet(setNumber: "5678-1", name: "Beta")

        listA.sets = [setA]
        listB.sets = [setB]
        setA.collection = listA
        setB.collection = listB

        let neededPartA = Part(
            partID: "3023",
            name: "Plate 1 x 2",
            colorID: "59",
            colorName: "Dark Red",
            quantityNeeded: 2,
            quantityHave: 0,
            set: setA
        )

        let ignoredExtra = Part(
            partID: "9999",
            name: "Spare",
            colorID: "99",
            colorName: "Spare",
            quantityNeeded: 1,
            quantityHave: 0,
            inventorySection: .extra,
            set: setA
        )

        let neededPartB = Part(
            partID: "3023",
            name: "Plate 1 x 2",
            colorID: "59",
            colorName: "Dark Red",
            quantityNeeded: 1,
            quantityHave: 0,
            set: setB
        )

        setA.parts = [neededPartA, ignoredExtra]
        setB.parts = [neededPartB]

        let inventory = WantedListExporter.makeInventory(from: [listA, listB])

        #expect(inventory.items.count == 1)
        let item = try #require(inventory.items.first)
        #expect(item.itemType == .part)
        #expect(item.itemID == "3023")
        #expect(item.color == "59")
        #expect(item.minQuantity == 3)
        #expect(item.remarks == "1234 (2), 5678 (1)")
    }

    @Test @MainActor
    func minifigureExportsWhenAllPartsMissing() throws {
        let list = CollectionList(name: "List")
        let set = BrickSet(setNumber: "7777-1", name: "Set")
        list.sets = [set]
        set.collection = list

        let figure = Minifigure(identifier: "fig-001", name: "Test Figure", quantityNeeded: 1, set: set)

        let head = Part(
            partID: "head",
            name: "Head",
            colorID: "1",
            colorName: "White",
            quantityNeeded: 1,
            quantityHave: 0,
            minifigure: figure
        )

        let torso = Part(
            partID: "torso",
            name: "Torso",
            colorID: "5",
            colorName: "Red",
            quantityNeeded: 1,
            quantityHave: 0,
            minifigure: figure
        )

        figure.parts = [head, torso]
        set.minifigures = [figure]

        let inventory = WantedListExporter.makeInventory(from: [list])

        #expect(inventory.items.count == 1)
        let item = try #require(inventory.items.first)
        #expect(item.itemType == .minifigure)
        #expect(item.itemID == "fig-001")
        #expect(item.color == nil)
        #expect(item.minQuantity == 1)
        #expect(item.remarks == "7777 (1)")
    }

    @Test @MainActor
    func minifigureExportsPartsWhenOnlySomeMissing() throws {
        let list = CollectionList(name: "List")
        let set = BrickSet(setNumber: "8888-1", name: "Set")
        list.sets = [set]
        set.collection = list

        let figure = Minifigure(identifier: "fig-002", name: "Partial Figure", quantityNeeded: 1, set: set)

        let head = Part(
            partID: "head",
            name: "Head",
            colorID: "1",
            colorName: "White",
            quantityNeeded: 1,
            quantityHave: 0,
            minifigure: figure
        )

        let torso = Part(
            partID: "torso",
            name: "Torso",
            colorID: "5",
            colorName: "Red",
            quantityNeeded: 1,
            quantityHave: 1,
            minifigure: figure
        )

        figure.parts = [head, torso]
        set.minifigures = [figure]

        let inventory = WantedListExporter.makeInventory(from: [list])

        #expect(inventory.items.count == 1)
        let item = try #require(inventory.items.first)
        #expect(item.itemType == .part)
        #expect(item.itemID == "head")
        #expect(item.color == "1")
        #expect(item.minQuantity == 1)
        #expect(item.remarks == "8888 (1)")
    }

    @Test @MainActor
    func partWithSubpartsExportsMissingChildren() throws {
        let list = CollectionList(name: "List")
        let set = BrickSet(setNumber: "41314-1", name: "Friends Set")
        list.sets = [set]
        set.collection = list

        let assembly = Part(
            partID: "93082",
            name: "Friends Accessories",
            colorID: "11",
            colorName: "Black",
            quantityNeeded: 1,
            quantityHave: 0,
            set: set
        )

        let hairBrush = Part(
            partID: "93081",
            name: "Hair Brush",
            colorID: "1",
            colorName: "White",
            quantityNeeded: 2,
            quantityHave: 1,
            parentPart: assembly
        )

        let ribbon = Part(
            partID: "93083",
            name: "Ribbon",
            colorID: "5",
            colorName: "Red",
            quantityNeeded: 3,
            quantityHave: 0,
            parentPart: assembly
        )

        assembly.subparts = [hairBrush, ribbon]
        set.parts = [assembly]

        let inventory = WantedListExporter.makeInventory(from: [list])

        #expect(inventory.items.count == 2)
        let brushItem = try #require(inventory.items.first { $0.itemID == "93081" })
        #expect(brushItem.minQuantity == 1)

        let ribbonItem = try #require(inventory.items.first { $0.itemID == "93083" })
        #expect(ribbonItem.minQuantity == 3)
        #expect(!inventory.items.contains { $0.itemID == "93082" })
    }

    @Test @MainActor
    func partWithSubpartsWithoutProgressExportsParentOnly() throws {
        let list = CollectionList(name: "List")
        let set = BrickSet(setNumber: "5555-1", name: "Set")
        list.sets = [set]
        set.collection = list

        let assembly = Part(
            partID: "assembly",
            name: "Assembly",
            colorID: "11",
            colorName: "Black",
            quantityNeeded: 2,
            quantityHave: 0,
            set: set
        )

        let childA = Part(
            partID: "childA",
            name: "Child A",
            colorID: "1",
            colorName: "White",
            quantityNeeded: 1,
            quantityHave: 0,
            parentPart: assembly
        )

        let childB = Part(
            partID: "childB",
            name: "Child B",
            colorID: "5",
            colorName: "Red",
            quantityNeeded: 1,
            quantityHave: 0,
            parentPart: assembly
        )

        assembly.subparts = [childA, childB]
        set.parts = [assembly]

        let inventory = WantedListExporter.makeInventory(from: [list])

        #expect(inventory.items.count == 1)
        let assemblyItem = try #require(inventory.items.first)
        #expect(assemblyItem.itemID == "assembly")
        #expect(assemblyItem.minQuantity == 2)
    }

    @Test @MainActor
    func minifigurePartSubcomponentsAreExportedWhenPartiallyComplete() throws {
        let list = CollectionList(name: "List")
        let set = BrickSet(setNumber: "9999-1", name: "Set")
        list.sets = [set]
        set.collection = list

        let minifigure = Minifigure(
            identifier: "fig-010",
            name: "Tester",
            quantityNeeded: 1,
            set: set
        )

        let helmet = Part(
            partID: "helmet",
            name: "Helmet",
            colorID: "11",
            colorName: "Black",
            quantityNeeded: 1,
            quantityHave: 0,
            minifigure: minifigure
        )

        let visor = Part(
            partID: "visor",
            name: "Visor",
            colorID: "1",
            colorName: "White",
            quantityNeeded: 1,
            quantityHave: 1,
            parentPart: helmet
        )

        let plume = Part(
            partID: "plume",
            name: "Plume",
            colorID: "5",
            colorName: "Red",
            quantityNeeded: 1,
            quantityHave: 0,
            parentPart: helmet
        )

        helmet.subparts = [visor, plume]
        minifigure.parts = [helmet]
        set.minifigures = [minifigure]

        let inventory = WantedListExporter.makeInventory(from: [list])

        #expect(inventory.items.count == 1)
        let plumeItem = try #require(inventory.items.first)
        #expect(plumeItem.itemID == "plume")
        #expect(plumeItem.minQuantity == 1)
        #expect(plumeItem.remarks == "9999 (1)")
    }
}
