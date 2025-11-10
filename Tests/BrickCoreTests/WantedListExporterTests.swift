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
        #expect(item.color == "0")
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
}
