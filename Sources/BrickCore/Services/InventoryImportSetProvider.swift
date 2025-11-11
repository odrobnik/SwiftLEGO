import Foundation
import SwiftData

public protocol BrickLinkSetProviding: Sendable {
    func fetchSetDetails(for setNumber: String) async throws -> BrickLinkSetPayload
}

extension BrickLinkService: BrickLinkSetProviding {}

public struct InventoryImportSetBlueprint: Sendable {
    public let setNumber: String
    public let defaultName: String
    public let thumbnailURLString: String?
    public let parts: [BrickLinkPartPayload]
    public let categories: [SetCategoryPayload]
    public let minifigures: [BrickLinkMinifigurePayload]

    public init(
        setNumber: String,
        defaultName: String,
        thumbnailURLString: String?,
        parts: [BrickLinkPartPayload],
        categories: [SetCategoryPayload],
        minifigures: [BrickLinkMinifigurePayload]
    ) {
        self.setNumber = setNumber
        self.defaultName = defaultName
        self.thumbnailURLString = thumbnailURLString
        self.parts = parts
        self.categories = categories
        self.minifigures = minifigures
    }

    public init(sourceSet: BrickSet) {
        self.init(
            setNumber: sourceSet.setNumber,
            defaultName: sourceSet.name,
            thumbnailURLString: sourceSet.thumbnailURLString,
            parts: SetImportUtilities.partPayloads(from: sourceSet.parts),
            categories: SetImportUtilities.categoryPayloads(from: sourceSet.categories),
            minifigures: SetImportUtilities.minifigurePayloads(from: sourceSet.minifigures)
        )
    }

    public init(payload: BrickLinkSetPayload) {
        self.init(
            setNumber: payload.setNumber,
            defaultName: payload.name,
            thumbnailURLString: payload.thumbnailURL?.absoluteString,
            parts: payload.parts,
            categories: payload.categories,
            minifigures: payload.minifigures
        )
    }
}

@MainActor
public final class InventoryImportSetProvider {
    private var cache: [String: InventoryImportSetBlueprint] = [:]
    private let modelContext: ModelContext
    private let service: BrickLinkSetProviding

    public init(modelContext: ModelContext, service: BrickLinkSetProviding) {
        self.modelContext = modelContext
        self.service = service
    }

    public func blueprint(for rawSetNumber: String) async throws -> InventoryImportSetBlueprint {
        let normalizedNumber = SetImportUtilities.normalizedSetNumber(rawSetNumber)
        let cacheKey = normalizedNumber.lowercased()

        if let cached = cache[cacheKey] {
            return cached
        }

        if let existing = try existingSet(withNormalizedNumber: normalizedNumber) {
            let blueprint = InventoryImportSetBlueprint(sourceSet: existing)
            cache[cacheKey] = blueprint
            return blueprint
        }

        let payload = try await service.fetchSetDetails(for: normalizedNumber)
        let blueprint = InventoryImportSetBlueprint(payload: payload)
        cache[cacheKey] = blueprint
        return blueprint
    }

    private func existingSet(withNormalizedNumber setNumber: String) throws -> BrickSet? {
        let descriptor = FetchDescriptor<BrickSet>(
            predicate: #Predicate { $0.setNumber == setNumber }
        )
        let sets = try modelContext.fetch(descriptor)
        return sets.first(where: { !$0.parts.isEmpty })
    }
}
