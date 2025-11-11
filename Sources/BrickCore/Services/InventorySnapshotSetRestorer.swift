import Foundation
import SwiftData

@MainActor
public final class InventorySnapshotSetRestorer {
    private let modelContext: ModelContext
    private let setProvider: InventoryImportSetProvider

    public init(modelContext: ModelContext, setProvider: InventoryImportSetProvider) {
        self.modelContext = modelContext
        self.setProvider = setProvider
    }

    @discardableResult
    public func importSet(
        _ setSnapshot: InventorySnapshot.SetSnapshot,
        into list: CollectionList
    ) async throws -> BrickSet {
        let blueprint = try await setProvider.blueprint(for: setSnapshot.setNumber)
        let resolvedThumbnail = setSnapshot.thumbnailURLString ?? blueprint.thumbnailURLString

        let importedSet = SetImportUtilities.persistSet(
            list: list,
            modelContext: modelContext,
            setNumber: blueprint.setNumber,
            defaultName: blueprint.defaultName,
            customName: setSnapshot.name,
            thumbnailURLString: resolvedThumbnail,
            parts: blueprint.parts,
            categories: blueprint.categories,
            minifigures: blueprint.minifigures
        )

        let synchronizationSnapshot = InventorySnapshot(sets: [setSnapshot])
        _ = synchronizationSnapshot.apply(to: [list])
        try? modelContext.save()
        return importedSet
    }
}
