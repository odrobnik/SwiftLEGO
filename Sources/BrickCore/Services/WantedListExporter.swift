import Foundation

public enum WantedListExporter {
    private static let defaultMaxPrice = "-1.0000"

    @MainActor
    public static func makeInventory(from lists: [CollectionList]) -> WantedListInventory {
        var aggregator = Aggregator()

        for list in lists {
            for set in list.sets {
                aggregator.collectMissingParts(from: set)
                aggregator.collectMissingMinifigures(from: set)
            }
        }

        return aggregator.makeInventory()
    }
}

private extension WantedListExporter {
    struct AggregationKey: Hashable {
        let itemType: WantedListItem.ItemType
        let itemID: String
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
            let rootParts = set.parts.filter { $0.parentPart == nil }
            for part in rootParts {
                collectMissingEntries(for: part, setNumber: set.setNumber)
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
                    return lhs.key.color.localizedStandardCompare(rhs.key.color) == .orderedAscending
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

            let allPartsMissing = regularParts.isEmpty || regularParts.allSatisfy { !Self.hierarchyHasOwnedQuantity($0) }

            if allPartsMissing {
                addMinifigure(
                    identifier: Self.trimmedIdentifier(minifigure.identifier),
                    quantity: missingFigures,
                    setNumber: set.setNumber
                )
                return
            }

            for part in regularParts {
                collectMissingEntries(for: part, setNumber: set.setNumber)
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
                color: "0",
                quantity: quantity,
                setNumber: setNumber
            )
        }

        private mutating func addEntry(
            itemType: WantedListItem.ItemType,
            itemID: String,
            color: String,
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

        private static func missingQuantity(for part: Part) -> Int {
            max(0, part.quantityNeeded - part.quantityHave)
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
        private mutating func collectMissingEntries(for part: Part, setNumber: String) -> Bool {
            guard part.inventorySection == .regular else { return false }

            if part.subparts.isEmpty {
                let missing = Self.missingQuantity(for: part)
                guard missing > 0 else { return false }
                addPart(
                    itemID: Self.trimmedIdentifier(part.partID),
                    color: Self.resolvedColorID(for: part),
                    quantity: missing,
                    setNumber: setNumber
                )
                return true
            }

            var didAdd = false
            for child in part.subparts {
                if collectMissingEntries(for: child, setNumber: setNumber) {
                    didAdd = true
                }
            }
            return didAdd
        }

        private static func hierarchyHasOwnedQuantity(_ part: Part) -> Bool {
            if part.quantityHave > 0 {
                return true
            }
            return part.subparts.contains { hierarchyHasOwnedQuantity($0) }
        }
    }
}
