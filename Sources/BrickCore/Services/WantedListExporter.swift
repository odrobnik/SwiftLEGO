import Foundation

public enum WantedListExporter {
    private static let defaultMaxPrice = "-1.0000"

    @MainActor
    public static func makeInventory(from lists: [CollectionList]) -> WantedListInventory {
        var aggregator = Aggregator()

        for list in lists {
            for set in list.sets {
                guard !set.excludeFromWantedList else { continue }
                aggregator.collectMissingParts(from: set)
                aggregator.collectMissingMinifigures(from: set)
            }
        }

        return aggregator.makeInventory()
    }

    @MainActor
    public static func makeInventory(from sets: [BrickSet]) -> WantedListInventory {
        var aggregator = Aggregator()

        for set in sets where !set.excludeFromWantedList {
            aggregator.collectMissingParts(from: set)
            aggregator.collectMissingMinifigures(from: set)
        }

        return aggregator.makeInventory()
    }
}

private extension WantedListExporter {
    struct AggregationKey: Hashable {
        let itemType: WantedListItem.ItemType
        let itemID: String
        let color: String?
    }

    struct StickerAllocationKey: Hashable {
        let partID: String
        let color: String
    }

    struct AggregationValue {
        var totalQuantity: Int = 0
        var perSetQuantities: [String: Int] = [:]

        mutating func add(quantity: Int, setID: String) {
            totalQuantity += quantity
            perSetQuantities[setID, default: 0] += quantity
        }

        func remarksDescription() -> String {
            perSetQuantities
                .sorted { lhs, rhs in
                    lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
                }
                .map { "\($0.key) (\($0.value))" }
                .joined(separator: ", ")
        }
    }

    struct Aggregator {
        private var entries: [AggregationKey: AggregationValue] = [:]

        mutating func collectMissingParts(from set: BrickSet) {
            var stickerAllocations = collectStickeredCounterparts(from: set)
            let rootParts = set.parts.filter { $0.parentPart == nil && $0.inventorySection == .regular }
            for part in rootParts {
                var overrideMissing: Int?
                if let trimmedID = Self.nonEmptyIdentifier(from: part.partID) {
                    let colorID = Self.resolvedColorID(for: part)
                    let key = StickerAllocationKey(partID: trimmedID, color: colorID)
                    if let allocation = stickerAllocations[key], allocation > 0 {
                        let baseMissing = part.missingQuantity
                        let adjusted = max(0, baseMissing - allocation)
                        let consumed = baseMissing - adjusted
                        stickerAllocations[key] = max(0, allocation - consumed)
                        overrideMissing = adjusted
                    }
                }
                collectMissingEntries(
                    for: part,
                    setNumber: set.setNumber,
                    overrideMissingQuantity: overrideMissing
                )
            }
        }

        mutating func collectMissingMinifigures(from set: BrickSet) {
            for minifigure in set.minifigures {
                addEntries(for: minifigure, in: set)
            }
        }

        func makeInventory() -> WantedListInventory {
            let items = entries
                .sorted { lhs, rhs in
                    if lhs.key.itemType != rhs.key.itemType {
                        return lhs.key.itemType.rawValue < rhs.key.itemType.rawValue
                    }
                    if lhs.key.itemID != rhs.key.itemID {
                        return lhs.key.itemID.localizedStandardCompare(rhs.key.itemID) == .orderedAscending
                    }
                    let lhsColor = lhs.key.color ?? ""
                    let rhsColor = rhs.key.color ?? ""
                    return lhsColor.localizedStandardCompare(rhsColor) == .orderedAscending
                }
                .map { entry in
                    WantedListItem(
                        itemType: entry.key.itemType,
                        itemID: entry.key.itemID,
                        color: entry.key.color,
                        maxPrice: WantedListExporter.defaultMaxPrice,
                        minQuantity: entry.value.totalQuantity,
                        remarks: entry.value.remarksDescription()
                    )
                }

            return WantedListInventory(items: items)
        }

        private mutating func addEntries(for minifigure: Minifigure, in set: BrickSet) {
            let missingFigures = Self.missingQuantity(for: minifigure)
            guard missingFigures > 0 else { return }

            let regularParts = minifigure.parts.filter {
                $0.inventorySection == .regular && $0.parentPart == nil
            }

            let allPartsMissing = regularParts.isEmpty || regularParts.allSatisfy { !$0.hasOwnedQuantityInHierarchy() }

            if allPartsMissing {
                addMinifigure(
                    identifier: Self.trimmedIdentifier(minifigure.identifier),
                    quantity: missingFigures,
                    setNumber: set.setNumber
                )
                return
            }

            for part in regularParts {
                collectMissingEntries(
                    for: part,
                    setNumber: set.setNumber,
                    overrideMissingQuantity: nil
                )
            }
        }

        private mutating func addPart(itemID: String, color: String, quantity: Int, setNumber: String) {
            addEntry(
                itemType: .part,
                itemID: itemID,
                color: color,
                quantity: quantity,
                setNumber: setNumber
            )
        }

        private mutating func addMinifigure(identifier: String, quantity: Int, setNumber: String) {
            addEntry(
                itemType: .minifigure,
                itemID: identifier,
                color: nil,
                quantity: quantity,
                setNumber: setNumber
            )
        }

        private mutating func addEntry(
            itemType: WantedListItem.ItemType,
            itemID: String,
            color: String?,
            quantity: Int,
            setNumber: String
        ) {
            guard quantity > 0 else { return }
            let trimmedItemID = itemID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedItemID.isEmpty else { return }
            let normalizedSetID = Self.displaySetIdentifier(for: setNumber)
            guard !normalizedSetID.isEmpty else { return }

            let key = AggregationKey(
                itemType: itemType,
                itemID: trimmedItemID,
                color: color
            )

            var value = entries[key] ?? AggregationValue()
            value.add(quantity: quantity, setID: normalizedSetID)
            entries[key] = value
        }

        private static func missingQuantity(for minifigure: Minifigure) -> Int {
            max(0, minifigure.quantityNeeded - minifigure.quantityHave)
        }

        private static func trimmedIdentifier(_ raw: String) -> String {
            raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private static func resolvedColorID(for part: Part) -> String {
            let trimmed = part.colorID.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "0" : trimmed
        }

        private static func displaySetIdentifier(for rawSetNumber: String) -> String {
            let trimmed = rawSetNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return trimmed }
            guard let hyphenIndex = trimmed.firstIndex(of: "-") else {
                return trimmed
            }
            return String(trimmed[..<hyphenIndex])
        }

        @discardableResult
        private mutating func collectMissingEntries(
            for part: Part,
            setNumber: String,
            overrideMissingQuantity: Int? = nil
        ) -> Bool {
            guard part.inventorySection == .regular else { return false }

            let missing = overrideMissingQuantity ?? part.missingQuantity
            guard missing > 0 else { return false }

            let trimmedID = Self.trimmedIdentifier(part.partID)
            guard !trimmedID.isEmpty else { return false }

            let shouldEmitSelf = part.subparts.isEmpty ||
                !part.hasOwnedQuantityInHierarchy() ||
                part.hasUniformMissingSubparts()

            if shouldEmitSelf {
                addPart(
                    itemID: trimmedID,
                    color: Self.resolvedColorID(for: part),
                    quantity: missing,
                    setNumber: setNumber
                )
                return true
            }

            var didAdd = false
            for child in part.subparts {
                if collectMissingEntries(for: child, setNumber: setNumber, overrideMissingQuantity: nil) {
                    didAdd = true
                }
            }
            return didAdd
        }

        private mutating func collectStickeredCounterparts(from set: BrickSet) -> [StickerAllocationKey: Int] {
            var allocations: [StickerAllocationKey: Int] = [:]
            let counterparts = set.parts.filter { $0.parentPart == nil && $0.inventorySection == .counterpart }

            for part in counterparts {
                guard Self.isStickeredCounterpart(part),
                      let stickerID = Self.nonEmptyIdentifier(from: part.partID),
                      let baseID = Self.basePartIdentifier(from: part.partID) else {
                    continue
                }

                let missing = part.missingQuantity
                guard missing > 0 else { continue }

                let colorID = Self.resolvedColorID(for: part)

                addPart(
                    itemID: stickerID,
                    color: colorID,
                    quantity: missing,
                    setNumber: set.setNumber
                )

                let key = StickerAllocationKey(partID: baseID, color: colorID)
                allocations[key, default: 0] += missing
            }

            return allocations
        }

        private static func isStickeredCounterpart(_ part: Part) -> Bool {
            guard part.inventorySection == .counterpart else { return false }
            let name = part.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.localizedCaseInsensitiveContains("sticker") else { return false }
            return basePartIdentifier(from: part.partID) != nil
        }

        private static func basePartIdentifier(from stickeredID: String) -> String? {
            let trimmed = trimmedIdentifier(stickeredID)
            guard !trimmed.isEmpty else { return nil }
            let lower = trimmed.lowercased()
            guard let range = lower.range(of: "pb") else { return nil }
            let base = trimmed[..<range.lowerBound]
            let sanitized = base.trimmingCharacters(in: .whitespacesAndNewlines)
            return sanitized.isEmpty ? nil : sanitized
        }

        private static func nonEmptyIdentifier(from raw: String) -> String? {
            let trimmed = trimmedIdentifier(raw)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}
