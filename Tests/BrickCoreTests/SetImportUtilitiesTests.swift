import Foundation
import SwiftData
import Testing
@testable import BrickCore

struct SetImportUtilitiesTests {
    @Test @MainActor
    func subpartsInheritParentColorWhenMissing() throws {
        let container = try SwiftLEGOModelContainer.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let list = CollectionList(name: "Test List")
        context.insert(list)

        let childPayload = BrickLinkPartPayload(
            partID: "child-1",
            name: "Child Part",
            colorID: "",
            colorName: "",
            quantityNeeded: 1,
            inventorySection: .regular
        )

        let parentPayload = BrickLinkPartPayload(
            partID: "parent-1",
            name: "Parent Part",
            colorID: "11",
            colorName: "Black",
            quantityNeeded: 1,
            inventorySection: .regular,
            subparts: [childPayload]
        )

        let set = SetImportUtilities.persistSet(
            list: list,
            modelContext: context,
            setNumber: "123-1",
            defaultName: "Test Set",
            customName: nil,
            thumbnailURLString: nil,
            parts: [parentPayload],
            categories: [],
            minifigures: []
        )

        let savedParent = try #require(set.parts.first)
        #expect(savedParent.colorID == "11")
        #expect(savedParent.colorName == "Black")

        let savedChild = try #require(savedParent.subparts.first)
        #expect(savedChild.colorID == "11")
        #expect(savedChild.colorName == "Black")
    }

    @Test @MainActor
    func importedSubpartsFrom41314InheritParentColor() async throws {
        let service = BrickLinkService()
        let payload = try await service.fetchSetDetails(for: "41314-1")

        let accessoriesPayload = try #require(
            payload.parts.first { $0.partID == "93082" && $0.colorID == "42" },
            "Expected to find part 93082 in Medium Blue."
        )

        let subpartsNeedingInheritance = accessoriesPayload.subparts.filter {
            let trimmedColor = $0.colorName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let trimmedName = $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return trimmedColor.isEmpty || trimmedColor == trimmedName
        }
        #expect(!subpartsNeedingInheritance.isEmpty, "Fixture should include subparts lacking distinct color names.")

        let container = try SwiftLEGOModelContainer.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let list = CollectionList(name: "Live Import")
        context.insert(list)

        let set = SetImportUtilities.persistSet(
            list: list,
            modelContext: context,
            setNumber: payload.setNumber,
            defaultName: payload.name,
            customName: nil,
            thumbnailURLString: payload.thumbnailURL?.absoluteString,
            parts: payload.parts,
            categories: payload.categories,
            minifigures: payload.minifigures
        )

        let savedAccessories = try #require(
            set.parts.first { $0.partID == "93082" && $0.colorID == "42" },
            "Persisted accessories should be present."
        )

        let expectedColorName = savedAccessories.colorName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        #expect(!expectedColorName.isEmpty)
        #expect(!savedAccessories.subparts.isEmpty)

        for subpart in savedAccessories.subparts {
            let resolvedColorName = subpart.colorName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            #expect(!resolvedColorName.isEmpty, "Subpart \(subpart.partID) should have a color after persistence.")
            #expect(
                resolvedColorName == expectedColorName,
                "Subpart \(subpart.partID) expected to inherit \(savedAccessories.colorName) but found \(subpart.colorName)."
            )
        }
    }
}
