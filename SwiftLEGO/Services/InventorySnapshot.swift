import Foundation
import SwiftData

struct InventorySnapshot: Codable, Sendable {
    struct SetSnapshot: Codable, Sendable {
        struct PartSnapshot: Codable, Sendable {
            let partID: String
            let colorID: String
            let quantityHave: Int
            let inventorySection: String?
            let subparts: [PartSnapshot]?

            init(
                partID: String,
                colorID: String,
                quantityHave: Int,
                inventorySection: String?,
                subparts: [PartSnapshot]? = nil
            ) {
                self.partID = partID
                self.colorID = colorID
                self.quantityHave = quantityHave
                self.inventorySection = inventorySection
                self.subparts = subparts
            }

            private enum CodingKeys: String, CodingKey {
                case partID
                case colorID
                case quantityHave
                case inventorySection
                case subparts
            }

            fileprivate var lookupKeys: [String] {
                let base = "\(partID.lowercased())|\(colorID.lowercased())"
                if let inventorySection, !inventorySection.isEmpty {
                    return ["\(base)|\(inventorySection.lowercased())", base]
                }
                return [base]
            }
        }

        struct MinifigureSnapshot: Codable, Sendable {
            let identifier: String
            let quantityHave: Int
            let parts: [PartSnapshot]
        }

        let setNumber: String
        let parts: [PartSnapshot]
        let minifigures: [MinifigureSnapshot]

        private enum CodingKeys: String, CodingKey {
            case setNumber
            case parts
            case minifigures
        }

        init(setNumber: String, parts: [PartSnapshot], minifigures: [MinifigureSnapshot] = []) {
            self.setNumber = setNumber
            self.parts = parts
            self.minifigures = minifigures
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            setNumber = try container.decode(String.self, forKey: .setNumber)
            parts = try container.decode([PartSnapshot].self, forKey: .parts)
            minifigures = try container.decodeIfPresent([MinifigureSnapshot].self, forKey: .minifigures) ?? []
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(setNumber, forKey: .setNumber)
            try container.encode(parts, forKey: .parts)
            if !minifigures.isEmpty {
                try container.encode(minifigures, forKey: .minifigures)
            }
        }
    }

    struct ApplyResult: Sendable {
        let updatedPartCount: Int
        let matchedSetCount: Int
        let unmatchedSetNumbers: [String]
        let unmatchedPartCount: Int

        var summaryDescription: String {
            var components: [String] = []
            components.append("Updated \(updatedPartCount) part\(updatedPartCount == 1 ? "" : "s")")
            components.append("across \(matchedSetCount) set\(matchedSetCount == 1 ? "" : "s")")

            if !unmatchedSetNumbers.isEmpty {
                components.append("Skipped \(unmatchedSetNumbers.count) missing set\(unmatchedSetNumbers.count == 1 ? "" : "s")")
            }

            if unmatchedPartCount > 0 {
                components.append("Ignored \(unmatchedPartCount) unmatched part\(unmatchedPartCount == 1 ? "" : "s")")
            }

            return components.joined(separator: "\n")
        }
    }

    static let empty = InventorySnapshot(sets: [])

    let sets: [SetSnapshot]
}

extension InventorySnapshot {
    @MainActor
    static func make(from lists: [CollectionList]) -> InventorySnapshot {
        let sets = lists
            .flatMap { $0.sets }
            .sorted { $0.setNumber.localizedCaseInsensitiveCompare($1.setNumber) == .orderedAscending }
            .map { set in
                let partSnapshots = set.parts.map { part in
                    SetSnapshot.PartSnapshot(
                        partID: part.partID,
                        colorID: part.colorID,
                        quantityHave: part.quantityHave,
                        inventorySection: part.inventorySection.rawValue,
                        subparts: makePartSnapshots(from: part.subparts)
                    )
                }
                .sorted(by: partSnapshotSortComparator)

                let minifigureSnapshots = set.minifigures
                    .sorted { $0.identifier.localizedCaseInsensitiveCompare($1.identifier) == .orderedAscending }
                    .map { minifigure in
                        let componentParts = minifigure.parts.map { part in
                            SetSnapshot.PartSnapshot(
                                partID: part.partID,
                                colorID: part.colorID,
                                quantityHave: part.quantityHave,
                                inventorySection: part.inventorySection.rawValue,
                                subparts: makePartSnapshots(from: part.subparts)
                            )
                        }
                        .sorted(by: partSnapshotSortComparator)

                        return SetSnapshot.MinifigureSnapshot(
                            identifier: minifigure.identifier,
                            quantityHave: minifigure.quantityHave,
                            parts: componentParts
                        )
                    }

                return SetSnapshot(
                    setNumber: set.setNumber,
                    parts: partSnapshots,
                    minifigures: minifigureSnapshots
                )
            }

        return InventorySnapshot(sets: sets)
    }

    @MainActor
    func apply(to lists: [CollectionList]) -> ApplyResult {
        let allSets = lists.flatMap { $0.sets }
        var setLookup: [String: BrickSet] = [:]

        for set in allSets {
            let key = normalizedSetKey(for: set.setNumber)
            setLookup[key] = set
        }

        var updatedPartCount = 0
        var matchedSetCount = 0
        var unmatchedSetNumbers: [String] = []
        var unmatchedPartCount = 0

        for setSnapshot in sets {
            guard let set = setLookup[normalizedSetKey(for: setSnapshot.setNumber)] else {
                unmatchedSetNumbers.append(setSnapshot.setNumber)
                continue
            }

            matchedSetCount += 1

            var partsLookup: [String: Part] = [:]
            for part in set.parts {
                insertPart(part, into: &partsLookup)
            }

            for partSnapshot in setSnapshot.parts {
                applyPartSnapshot(
                    partSnapshot,
                    parts: set.parts,
                    precomputedLookup: partsLookup,
                    updatedPartCount: &updatedPartCount,
                    unmatchedPartCount: &unmatchedPartCount
                )
            }

            if !setSnapshot.minifigures.isEmpty {
                var minifigureLookup: [String: Minifigure] = [:]
                for minifigure in set.minifigures {
                    let key = minifigure.identifier.lowercased()
                    if minifigureLookup[key] == nil {
                        minifigureLookup[key] = minifigure
                    }
                }

                for minifigureSnapshot in setSnapshot.minifigures {
                    let identifierKey = minifigureSnapshot.identifier.lowercased()
                    guard let minifigure = minifigureLookup[identifierKey] else {
                        unmatchedPartCount += 1
                        continue
                    }

                    let clampedQuantity = max(0, min(minifigureSnapshot.quantityHave, minifigure.quantityNeeded))
                    if minifigure.quantityHave != clampedQuantity {
                        minifigure.quantityHave = clampedQuantity
                        updatedPartCount += 1
                    }

                    var minifigurePartsLookup: [String: Part] = [:]
                    for part in minifigure.parts {
                        insertPart(part, into: &minifigurePartsLookup)
                    }

                    for partSnapshot in minifigureSnapshot.parts {
                        applyPartSnapshot(
                            partSnapshot,
                            parts: minifigure.parts,
                            precomputedLookup: minifigurePartsLookup,
                            updatedPartCount: &updatedPartCount,
                            unmatchedPartCount: &unmatchedPartCount
                        )
                    }
                }
            }
        }

        return ApplyResult(
            updatedPartCount: updatedPartCount,
            matchedSetCount: matchedSetCount,
            unmatchedSetNumbers: unmatchedSetNumbers,
            unmatchedPartCount: unmatchedPartCount
        )
    }

    private func normalizedSetKey(for setNumber: String) -> String {
        SetImportUtilities.normalizedSetNumber(setNumber).lowercased()
    }

    private static func makePartSnapshots(from parts: [Part]) -> [SetSnapshot.PartSnapshot]? {
        let sorted = parts.sorted(by: partSortComparator)
        guard !sorted.isEmpty else { return nil }
        return sorted.map { part in
            SetSnapshot.PartSnapshot(
                partID: part.partID,
                colorID: part.colorID,
                quantityHave: part.quantityHave,
                inventorySection: part.inventorySection.rawValue,
                subparts: makePartSnapshots(from: part.subparts)
            )
        }
    }

    private static func partSortComparator(_ lhs: Part, _ rhs: Part) -> Bool {
        if lhs.partID.caseInsensitiveCompare(rhs.partID) != .orderedSame {
            return lhs.partID.localizedCaseInsensitiveCompare(rhs.partID) == .orderedAscending
        }

        if lhs.colorID.caseInsensitiveCompare(rhs.colorID) != .orderedSame {
            return lhs.colorID.localizedCaseInsensitiveCompare(rhs.colorID) == .orderedAscending
        }

        return lhs.inventorySectionRawValue.localizedCaseInsensitiveCompare(rhs.inventorySectionRawValue) == .orderedAscending
    }

    private static func partSnapshotSortComparator(
        _ lhs: SetSnapshot.PartSnapshot,
        _ rhs: SetSnapshot.PartSnapshot
    ) -> Bool {
        if lhs.partID.caseInsensitiveCompare(rhs.partID) != .orderedSame {
            return lhs.partID.localizedCaseInsensitiveCompare(rhs.partID) == .orderedAscending
        }

        if lhs.colorID.caseInsensitiveCompare(rhs.colorID) != .orderedSame {
            return lhs.colorID.localizedCaseInsensitiveCompare(rhs.colorID) == .orderedAscending
        }

        let lhsSection = lhs.inventorySection ?? ""
        let rhsSection = rhs.inventorySection ?? ""
        return lhsSection.localizedCaseInsensitiveCompare(rhsSection) == .orderedAscending
    }

    private func applyPartSnapshot(
        _ snapshot: SetSnapshot.PartSnapshot,
        parts: [Part],
        precomputedLookup: [String: Part]? = nil,
        updatedPartCount: inout Int,
        unmatchedPartCount: inout Int
    ) {
        let lookup = precomputedLookup ?? makePartLookup(from: parts)

        guard
            let key = snapshot.lookupKeys.first(where: { lookup[$0] != nil }),
            let part = lookup[key]
        else {
            unmatchedPartCount += 1
            return
        }

        let clampedValue = max(0, min(snapshot.quantityHave, part.quantityNeeded))
        if part.quantityHave != clampedValue {
            part.quantityHave = clampedValue
            updatedPartCount += 1
        }

        if let childSnapshots = snapshot.subparts, !childSnapshots.isEmpty {
            let childLookup = makePartLookup(from: part.subparts)
            for childSnapshot in childSnapshots {
                applyPartSnapshot(
                    childSnapshot,
                    parts: part.subparts,
                    precomputedLookup: childLookup,
                    updatedPartCount: &updatedPartCount,
                    unmatchedPartCount: &unmatchedPartCount
                )
            }
        }
    }

    private func makePartLookup(from parts: [Part]) -> [String: Part] {
        var lookup: [String: Part] = [:]
        for part in parts {
            insertPart(part, into: &lookup)
        }
        return lookup
    }

    private func insertPart(_ part: Part, into lookup: inout [String: Part]) {
        let baseKey = "\(part.partID.lowercased())|\(part.colorID.lowercased())"
        let sectionKey = "\(baseKey)|\(part.inventorySection.rawValue.lowercased())"

        if lookup[sectionKey] == nil {
            lookup[sectionKey] = part
        }

        if lookup[baseKey] == nil {
            lookup[baseKey] = part
        }
    }
}
