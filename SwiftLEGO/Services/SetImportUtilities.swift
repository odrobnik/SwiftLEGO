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
                inventorySection: sample.inventorySection,
                subparts: sample.subparts
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

    private static func makePartModel(
        from payload: BrickLinkPartPayload,
        set: BrickSet?,
        minifigure: Minifigure?,
        parentPart: Part?,
        multiplier: Int = 1
    ) -> Part {
        let totalNeeded = payload.quantityNeeded * multiplier
        let owningSet = parentPart == nil ? set : nil
        let owningMinifigure = parentPart == nil ? minifigure : nil

        let part = Part(
            partID: payload.partID,
            name: payload.name,
            colorID: payload.colorID,
            colorName: payload.colorName,
            quantityNeeded: totalNeeded,
            quantityHave: 0,
            imageURLString: payload.imageURL?.absoluteString,
            partURLString: payload.partURL?.absoluteString,
            inventorySection: payload.inventorySection,
            set: owningSet,
            minifigure: owningMinifigure,
            subparts: [],
            parentPart: parentPart
        )

        if !payload.subparts.isEmpty {
            let childMultiplier = totalNeeded
            part.subparts = payload.subparts.map {
                makePartModel(
                    from: $0,
                    set: set,
                    minifigure: minifigure,
                    parentPart: part,
                    multiplier: childMultiplier
                )
            }
        }

        return part
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
                inventorySection: $0.inventorySection,
                subparts: partPayloads(from: $0.subparts)
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

    static func minifigurePayloads(from minifigures: [Minifigure]) -> [BrickLinkMinifigurePayload] {
        minifigures.map { minifigure in
            BrickLinkMinifigurePayload(
                identifier: minifigure.identifier,
                name: minifigure.name,
                quantityNeeded: minifigure.quantityNeeded,
                imageURL: minifigure.imageURL,
                catalogURL: minifigure.catalogURL,
                inventoryURL: minifigure.inventoryURL,
                categories: minifigure.categories.sortedByOrder().map { category in
                    MinifigCategoryPayload(
                        id: category.categoryID,
                        name: category.name
                    )
                },
                parts: partPayloads(from: minifigure.parts)
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
        categories: [SetCategoryPayload],
        minifigures: [BrickLinkMinifigurePayload]
    ) -> BrickSet {
        let trimmedCustomName = customName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = (trimmedCustomName?.isEmpty == false ? trimmedCustomName! : defaultName)

        let newSet = BrickSet(
            setNumber: setNumber,
            name: finalName,
            thumbnailURLString: thumbnailURLString
        )

        let aggregatedParts = aggregateParts(parts)

        let partModels = aggregatedParts.map { payload in
            makePartModel(
                from: payload,
                set: newSet,
                minifigure: nil,
                parentPart: nil
            )
        }

        var categoryModels: [SetCategory] = []
        var previousCategory: SetCategory?

        for (index, category) in categories.enumerated() {
            let categoryModel = SetCategory(
                categoryID: category.id,
                name: category.name,
                sortOrder: index,
                set: newSet,
                parent: previousCategory
            )

            previousCategory?.children.append(categoryModel)

            categoryModels.append(categoryModel)
            previousCategory = categoryModel
        }

        let minifigureModels = makeMinifigureModels(
            from: minifigures,
            set: newSet
        )

        newSet.parts = partModels
        newSet.categories = categoryModels
        newSet.minifigures = minifigureModels
        newSet.collection = list
        list.sets.append(newSet)
        modelContext.insert(newSet)
        try? modelContext.save()
        return newSet
    }

    private static func makeMinifigureModels(
        from payloads: [BrickLinkMinifigurePayload],
        set: BrickSet
    ) -> [Minifigure] {
        payloads.enumerated().map { _, payload in
            let minifigure = Minifigure(
                identifier: payload.identifier,
                name: payload.name,
                quantityNeeded: payload.quantityNeeded,
                quantityHave: 0,
                imageURLString: payload.imageURL?.absoluteString,
                catalogURLString: payload.catalogURL?.absoluteString,
                inventoryURLString: payload.inventoryURL?.absoluteString,
                set: set
            )

            var categoryModels: [MinifigCategory] = []
            var previousCategory: MinifigCategory?

            for (index, category) in payload.categories.enumerated() {
                let categoryModel = MinifigCategory(
                    categoryID: category.id,
                    name: category.name,
                    sortOrder: index,
                    minifigure: minifigure,
                    parent: previousCategory
                )

                previousCategory?.children.append(categoryModel)
                categoryModels.append(categoryModel)
                previousCategory = categoryModel
            }

            minifigure.categories = categoryModels

            let aggregatedParts = aggregateParts(payload.parts)
            let partModels = aggregatedParts.map { partPayload in
                makePartModel(
                    from: partPayload,
                    set: nil,
                    minifigure: minifigure,
                    parentPart: nil
                )
            }

            minifigure.parts = partModels
            return minifigure
        }
    }
}
