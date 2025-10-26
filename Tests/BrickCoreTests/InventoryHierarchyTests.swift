import Testing
@testable import BrickCore

struct InventoryHierarchyTests {
    @Test @MainActor
    func parentPartCompletesWhenSubpartsFilled() {
        let parent = Part(
            partID: "parent",
            name: "Parent Part",
            colorID: "0",
            colorName: "None",
            quantityNeeded: 1
        )

        let firstChild = Part(
            partID: "child-a",
            name: "Child A",
            colorID: "0",
            colorName: "None",
            quantityNeeded: 1,
            parentPart: parent
        )

        let secondChild = Part(
            partID: "child-b",
            name: "Child B",
            colorID: "0",
            colorName: "None",
            quantityNeeded: 1,
            parentPart: parent
        )

        parent.subparts = [firstChild, secondChild]

        firstChild.quantityHave = 1
        firstChild.propagateCompletionUpwardsIfNeeded()
        #expect(parent.quantityHave == 0, "Parent should remain incomplete until all subparts are filled.")

        secondChild.quantityHave = 1
        secondChild.propagateCompletionUpwardsIfNeeded()
        #expect(parent.quantityHave == 1, "Parent should mark complete once every subpart meets its required quantity.")
    }

    @Test @MainActor
    func minifigureCompletesWhenPartsFilled() {
        let figure = Minifigure(
            identifier: "fig-001",
            name: "Tester",
            quantityNeeded: 1
        )

        let head = Part(
            partID: "head",
            name: "Head",
            colorID: "0",
            colorName: "None",
            quantityNeeded: 1,
            minifigure: figure
        )

        let torso = Part(
            partID: "torso",
            name: "Torso",
            colorID: "0",
            colorName: "None",
            quantityNeeded: 1,
            minifigure: figure
        )

        figure.parts = [head, torso]

        head.quantityHave = 1
        head.propagateCompletionUpwardsIfNeeded()
        #expect(figure.quantityHave == 0, "Figure should not complete until all parts are available.")

        torso.quantityHave = 1
        torso.propagateCompletionUpwardsIfNeeded()
        #expect(figure.quantityHave == 1, "Figure should complete when all parts meet their required quantities.")
    }

    @Test @MainActor
    func synchronizingMinifigureQuantityFillsPartsAndSubparts() {
        let figure = Minifigure(
            identifier: "fig-002",
            name: "Builder",
            quantityNeeded: 1
        )

        let accessory = Part(
            partID: "accessory",
            name: "Accessory",
            colorID: "0",
            colorName: "None",
            quantityNeeded: 1,
            minifigure: figure
        )

        let accessoryDetail = Part(
            partID: "detail",
            name: "Accessory Detail",
            colorID: "0",
            colorName: "None",
            quantityNeeded: 1,
            parentPart: accessory
        )

        accessory.subparts = [accessoryDetail]
        figure.parts = [accessory]

        figure.quantityHave = 1
        figure.synchronizeParts(to: figure.quantityHave)

        #expect(accessory.quantityHave == accessory.quantityNeeded, "Top-level parts should match their required quantity.")
        #expect(accessoryDetail.quantityHave == accessoryDetail.quantityNeeded, "Nested subparts should also synchronize to their required quantity.")
    }

    @Test @MainActor
    func synchronizingPartQuantityScalesSubparts() {
        let parent = Part(
            partID: "assembly",
            name: "Assembly",
            colorID: "0",
            colorName: "None",
            quantityNeeded: 2
        )

        let multiChild = Part(
            partID: "multi",
            name: "Multi Child",
            colorID: "0",
            colorName: "None",
            quantityNeeded: 6,
            parentPart: parent
        )

        let singleChild = Part(
            partID: "single",
            name: "Single Child",
            colorID: "0",
            colorName: "None",
            quantityNeeded: 2,
            parentPart: parent
        )

        parent.subparts = [multiChild, singleChild]

        parent.quantityHave = 1
        parent.synchronizeSubparts(to: parent.quantityHave)

        #expect(multiChild.quantityHave == 3, "Subparts should scale with the parent quantity (6 needed for two assemblies).")
        #expect(singleChild.quantityHave == 1, "Subparts should scale proportionally when the parent quantity is partial.")

        parent.quantityHave = 0
        parent.synchronizeSubparts(to: parent.quantityHave)

        #expect(multiChild.quantityHave == 0)
        #expect(singleChild.quantityHave == 0)
    }
}
