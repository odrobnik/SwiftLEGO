import Foundation
import SwiftData
import Testing
@testable import BrickCore

@MainActor
struct SetRefreshTests {
    private static let payload = BrickLinkSetPayload(
        setNumber: "6086-1",
        name: "Black Knight's Castle",
        parts: [
            BrickLinkPartPayload(
                partID: "3001",
                name: "Brick 2 x 4",
                colorID: "11",
                colorName: "Black",
                quantityNeeded: 4,
                inventorySection: .regular
            )
        ],
        categories: [],
        minifigures: [
            BrickLinkMinifigurePayload(
                identifier: "cas105",
                name: "Black Knight",
                quantityNeeded: 1
            )
        ]
    )

    @Test
    func refreshingOneCopyLeavesTheOtherCopyAlone() async throws {
        let context = try makeInMemoryModelContext()
        let list = CollectionList(name: "Castles")
        context.insert(list)

        let first = persistCopy(in: list, context: context)
        let second = persistCopy(in: list, context: context)
        SetImportUtilities.applyInstanceNumbering(
            for: Self.payload.setNumber,
            in: list,
            preferredName: Self.payload.name,
            modelContext: context
        )

        try brick(of: first).quantityHave = 1
        try brick(of: second).quantityHave = 3
        try knight(of: second).quantityHave = 1
        try context.save()

        let service = MockBrickLinkService()
        await service.setPayload(Self.payload, for: Self.payload.setNumber)

        try await SetImportUtilities.refreshSetFromBrickLink(set: second, modelContext: context, setProvider: service)
        try await SetImportUtilities.refreshSetFromBrickLink(set: first, modelContext: context, setProvider: service)

        #expect(try brick(of: first).quantityHave == 1)
        #expect(try knight(of: first).quantityHave == 0)
        #expect(try brick(of: second).quantityHave == 3)
        #expect(try knight(of: second).quantityHave == 1)
    }

    @Test
    func editsMadeWhileFetchingSurviveTheRefresh() async throws {
        let context = try makeInMemoryModelContext()
        let list = CollectionList(name: "Castles")
        context.insert(list)

        let set = persistCopy(in: list, context: context)
        let countedBrick = try brick(of: set)
        countedBrick.quantityHave = 1
        try context.save()

        // The set stays editable while BrickLink is being fetched.
        let provider = EditingSetProvider(payload: Self.payload) {
            countedBrick.quantityHave = 2
        }

        try await SetImportUtilities.refreshSetFromBrickLink(set: set, modelContext: context, setProvider: provider)

        #expect(try brick(of: set).quantityHave == 2)
        #expect(set.parts.count == 1, "The refresh should replace the inventory, not add to it.")
    }

    /// The app saves right after deleting a set; an unsaved deletion is one
    /// still pending when the refresh lands.
    @Test(arguments: [true, false])
    func aSetDeletedWhileFetchingStaysDeleted(deletionIsSaved: Bool) async throws {
        let context = try makeInMemoryModelContext()
        let list = CollectionList(name: "Castles")
        context.insert(list)

        let set = persistCopy(in: list, context: context)

        // Deleted from its grid while the refresh it started there is still fetching.
        let provider = EditingSetProvider(payload: Self.payload) {
            context.delete(set)
            if deletionIsSaved {
                try? context.save()
            }
        }

        try await SetImportUtilities.refreshSetFromBrickLink(set: set, modelContext: context, setProvider: provider)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<BrickSet>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Part>()) == 0, "The refresh should leave no parts behind for a deleted set.")
        #expect(try context.fetchCount(FetchDescriptor<Minifigure>()) == 0)
    }

    // MARK: - Helpers

    private func persistCopy(in list: CollectionList, context: ModelContext) -> BrickSet {
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

    private func brick(of set: BrickSet) throws -> Part {
        try #require(set.parts.first { $0.partID == "3001" })
    }

    private func knight(of set: BrickSet) throws -> Minifigure {
        try #require(set.minifigures.first { $0.identifier == "cas105" })
    }
}

/// Makes an edit before handing out its payload, as the user can while the
/// real fetch is in flight.
@MainActor
private final class EditingSetProvider: BrickLinkSetProviding {
    private let payload: BrickLinkSetPayload
    private let edit: () -> Void

    init(payload: BrickLinkSetPayload, edit: @escaping () -> Void) {
        self.payload = payload
        self.edit = edit
    }

    func fetchSetDetails(for setNumber: String) async throws -> BrickLinkSetPayload {
        edit()
        return payload
    }
}
