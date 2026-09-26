import Foundation
import SwiftData
import Testing
@testable import BrickCore

/// A list can hold several copies of one set number, each with its own
/// progress, so applying a snapshot has to keep them apart.
@MainActor
struct InventorySnapshotDuplicateCopiesTests {
    private static let setNumber = "6086-1"

    @Test
    func copiesAreMatchedByID() throws {
        let context = try makeInMemoryModelContext()
        let (list, first, second) = makeListWithTwoCopies(in: context)

        // Listed out of order and with swapped names, so only the IDs pair them up correctly.
        let snapshot = InventorySnapshot(sets: [
            makeSnapshot(id: second.id, name: first.name, bricks: 3),
            makeSnapshot(id: first.id, name: second.name, bricks: 1)
        ])

        let result = snapshot.apply(to: [list])
        try context.save()

        #expect(result.matchedSetCount == 2)
        #expect(result.unmatchedSetNumbers.isEmpty)
        #expect(try bricks(in: first) == 1)
        #expect(try bricks(in: second) == 3)
    }

    @Test
    func snapshotsWithoutIDsPreferTheCopyWithTheSameName() throws {
        let context = try makeInMemoryModelContext()
        let (list, first, second) = makeListWithTwoCopies(in: context)

        let snapshot = InventorySnapshot(sets: [
            makeSnapshot(id: nil, name: second.name, bricks: 3),
            makeSnapshot(id: nil, name: first.name, bricks: 1)
        ])

        let result = snapshot.apply(to: [list])
        try context.save()

        #expect(result.matchedSetCount == 2)
        #expect(try bricks(in: first) == 1)
        #expect(try bricks(in: second) == 3)
    }

    @Test
    func snapshotsWithoutIDsNeverShareACopy() throws {
        let context = try makeInMemoryModelContext()
        let (list, first, second) = makeListWithTwoCopies(in: context)

        // Like an older file: no IDs or names, and one copy more than the list holds.
        let snapshot = InventorySnapshot(sets: [
            makeSnapshot(id: nil, name: nil, bricks: 1),
            makeSnapshot(id: nil, name: nil, bricks: 3),
            makeSnapshot(id: nil, name: nil, bricks: 2)
        ])

        let result = snapshot.apply(to: [list])
        try context.save()

        #expect(result.matchedSetCount == 2)
        #expect(result.unmatchedSetNumbers == [Self.setNumber])
        #expect(try [bricks(in: first), bricks(in: second)].sorted() == [1, 3])
    }

    // MARK: - Helpers

    private func makeListWithTwoCopies(in context: ModelContext) -> (list: CollectionList, first: BrickSet, second: BrickSet) {
        let list = CollectionList(name: "Castles")
        context.insert(list)

        let brick = BrickLinkPartPayload(
            partID: "3001",
            name: "Brick 2 x 4",
            colorID: "11",
            colorName: "Black",
            quantityNeeded: 4,
            inventorySection: .regular
        )

        let copies = (0..<2).map { _ in
            SetImportUtilities.persistSet(
                list: list,
                modelContext: context,
                setNumber: Self.setNumber,
                defaultName: "Black Knight's Castle",
                customName: nil,
                thumbnailURLString: nil,
                parts: [brick],
                categories: [],
                minifigures: []
            )
        }

        SetImportUtilities.applyInstanceNumbering(
            for: Self.setNumber,
            in: list,
            preferredName: "Black Knight's Castle",
            modelContext: context
        )

        return (list, copies[0], copies[1])
    }

    private func makeSnapshot(id: UUID?, name: String?, bricks: Int) -> InventorySnapshot.SetSnapshot {
        InventorySnapshot.SetSnapshot(
            id: id,
            setNumber: Self.setNumber,
            name: name,
            parts: [
                InventorySnapshot.SetSnapshot.PartSnapshot(
                    partID: "3001",
                    colorID: "11",
                    quantityHave: bricks,
                    inventorySection: Part.InventorySection.regular.rawValue,
                    instanceNumber: nil
                )
            ]
        )
    }

    private func bricks(in set: BrickSet) throws -> Int {
        try #require(set.parts.first).quantityHave
    }
}
