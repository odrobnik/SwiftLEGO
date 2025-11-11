import Foundation
import Testing
@testable import BrickCore

@MainActor
struct InventoryImportSetProviderTests {
    @Test
    func returnsExistingBlueprintWithoutFetching() async throws {
        let context = try makeInMemoryModelContext()
        let list = CollectionList(name: "Existing")
        let set = BrickSet(setNumber: "10220-1", name: "Volkswagen T1 Camper Van")
        let part = Part(
            partID: "3001",
            name: "Brick 2 x 4",
            colorID: "5",
            colorName: "Red",
            quantityNeeded: 24,
            quantityHave: 12,
            set: set
        )
        set.parts = [part]
        set.collection = list
        list.sets = [set]
        context.insert(list)
        try context.save()

        let mockService = MockBrickLinkService()
        let provider = InventoryImportSetProvider(modelContext: context, service: mockService)

        let blueprint = try await provider.blueprint(for: "10220-1")

        #expect(blueprint.setNumber == "10220-1")
        #expect(blueprint.defaultName == "Volkswagen T1 Camper Van")
        #expect(blueprint.parts.count == 1)
        #expect(await mockService.recordedRequests().isEmpty)
    }

    @Test
    func fetchesAndCachesWhenSetMissing() async throws {
        let context = try makeInMemoryModelContext()
        let mockService = MockBrickLinkService()

        let partPayload = BrickLinkPartPayload(
            partID: "3001",
            name: "Brick 2 x 4",
            colorID: "5",
            colorName: "Red",
            quantityNeeded: 12,
            inventorySection: .regular
        )

        let payload = BrickLinkSetPayload(
            setNumber: "21108-1",
            name: "Ghostbusters Ecto-1",
            thumbnailURL: URL(string: "https://example.com/thumb.png"),
            parts: [partPayload],
            categories: [],
            minifigures: []
        )

        await mockService.setPayload(payload, for: "21108-1")

        let provider = InventoryImportSetProvider(modelContext: context, service: mockService)
        let blueprint = try await provider.blueprint(for: "21108")

        #expect(blueprint.setNumber == "21108-1")
        #expect(blueprint.defaultName == "Ghostbusters Ecto-1")
        #expect(blueprint.thumbnailURLString == "https://example.com/thumb.png")
        #expect(blueprint.parts.count == 1)

        let requestsAfterFirstFetch = await mockService.recordedRequests()
        #expect(requestsAfterFirstFetch == ["21108-1"])

        let cachedBlueprint = try await provider.blueprint(for: "21108-1")
        #expect(cachedBlueprint.setNumber == "21108-1")

        let requestsAfterSecondFetch = await mockService.recordedRequests()
        #expect(requestsAfterSecondFetch == ["21108-1"])
    }
}
