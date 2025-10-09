import Foundation
import SwiftData

enum SetImportUtilities {
    /// Normalizes BrickLink set numbers by ensuring they include a `-` suffix when missing.
    static func normalizedSetNumber(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return trimmed }

        if trimmed.contains("-") {
            return trimmed
        }

        return "\(trimmed)-1"
    }

    /// Aggregates parts sharing the same partID/colorID and sorts them for stable presentation.
    static func aggregateParts(_ parts: [BrickLinkPartPayload]) -> [BrickLinkPartPayload] {
        struct PartGroupKey: Hashable {
            let partID: String
            let colorID: String
            let inventorySection: Part.InventorySection
        }

        let grouped = Dictionary(grouping: parts) { PartGroupKey(partID: $0.partID, colorID: $0.colorID, inventorySection: $0.inventorySection) }

        return grouped.map { (_, group) in
            guard let sample = group.first else { fatalError("Unexpected empty group") }
            let totalNeeded = group.reduce(0) { $0 + $1.quantityNeeded }

            return BrickLinkPartPayload(
                partID: sample.partID,
                name: sample.name,
                colorID: sample.colorID,
                colorName: sample.colorName,
                quantityNeeded: totalNeeded,
                imageURL: sample.imageURL,
                partURL: sample.partURL,
                inventorySection: sample.inventorySection
            )
        }
        .sorted { lhs, rhs in
            if lhs.inventorySection != rhs.inventorySection {
                return lhs.inventorySection.sortOrder < rhs.inventorySection.sortOrder
            }

            if lhs.colorName != rhs.colorName {
                return lhs.colorName < rhs.colorName
            }

            if lhs.name != rhs.name {
                return lhs.name < rhs.name
            }

            return lhs.partID < rhs.partID
        }
    }

    static func partPayloads(from parts: [Part]) -> [BrickLinkPartPayload] {
        parts.map {
            BrickLinkPartPayload(
                partID: $0.partID,
                name: $0.name,
                colorID: $0.colorID,
                colorName: $0.colorName,
                quantityNeeded: $0.quantityNeeded,
                imageURL: $0.imageURL,
                partURL: $0.partURL,
                inventorySection: $0.inventorySection
            )
        }
    }

    static func categoryPayloads(from categories: [SetCategory]) -> [SetCategoryPayload] {
        categories
            .sortedByOrder()
            .map { category in
                SetCategoryPayload(
                    id: category.categoryID,
                    name: category.name
                )
            }
    }

    @MainActor
    static func persistSet(
        list: CollectionList,
        modelContext: ModelContext,
        setNumber: String,
        defaultName: String,
        customName: String?,
        thumbnailURLString: String?,
        parts: [BrickLinkPartPayload],
        categories: [SetCategoryPayload]
    ) -> BrickSet {
        let trimmedCustomName = customName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = (trimmedCustomName?.isEmpty == false ? trimmedCustomName! : defaultName)

        let newSet = BrickSet(
            setNumber: setNumber,
            name: finalName,
            thumbnailURLString: thumbnailURLString
        )

        let aggregatedParts = aggregateParts(parts)

        let partModels = aggregatedParts.map { part in
            Part(
                partID: part.partID,
                name: part.name,
                colorID: part.colorID,
                colorName: part.colorName,
                quantityNeeded: part.quantityNeeded,
                quantityHave: 0,
                imageURLString: part.imageURL?.absoluteString,
                partURLString: part.partURL?.absoluteString,
                inventorySection: part.inventorySection,
                set: newSet
            )
        }

        let categoryModels = categories.enumerated().map { index, category in
            SetCategory(
                categoryID: category.id,
                name: category.name,
                sortOrder: index,
                set: newSet
            )
        }

        newSet.parts = partModels
        newSet.categories = categoryModels
        newSet.collection = list
        list.sets.append(newSet)
        modelContext.insert(newSet)
        try? modelContext.save()
        return newSet
    }
}
