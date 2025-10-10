import Foundation
import SwiftData

struct InventorySnapshot: Codable, Sendable {
    struct SetSnapshot: Codable, Sendable {
        struct PartSnapshot: Codable, Sendable {
            let partID: String
            let colorID: String
            let quantityHave: Int
            let inventorySection: String?

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
                        inventorySection: part.inventorySection.rawValue
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.partID != rhs.partID {
                        return lhs.partID.localizedCaseInsensitiveCompare(rhs.partID) == .orderedAscending
                    }
                    return lhs.colorID.localizedCaseInsensitiveCompare(rhs.colorID) == .orderedAscending
                }

                let minifigureSnapshots = set.minifigures
                    .sorted { $0.identifier.localizedCaseInsensitiveCompare($1.identifier) == .orderedAscending }
                    .map { minifigure in
                        let componentParts = minifigure.parts.map { part in
                            SetSnapshot.PartSnapshot(
                                partID: part.partID,
                                colorID: part.colorID,
                                quantityHave: part.quantityHave,
                                inventorySection: part.inventorySection.rawValue
                            )
                        }
                        .sorted { lhs, rhs in
                            if lhs.partID != rhs.partID {
                                return lhs.partID.localizedCaseInsensitiveCompare(rhs.partID) == .orderedAscending
                            }
                            return lhs.colorID.localizedCaseInsensitiveCompare(rhs.colorID) == .orderedAscending
                        }

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
                let baseKey = "\(part.partID.lowercased())|\(part.colorID.lowercased())"
                let sectionKey = "\(baseKey)|\(part.inventorySection.rawValue.lowercased())"

                if partsLookup[sectionKey] == nil {
                    partsLookup[sectionKey] = part
                }

                if partsLookup[baseKey] == nil {
                    partsLookup[baseKey] = part
                }
            }

            for partSnapshot in setSnapshot.parts {
                guard
                    let key = partSnapshot.lookupKeys.first(where: { partsLookup[$0] != nil }),
                    let part = partsLookup[key]
                else {
                    unmatchedPartCount += 1
                    continue
                }

                let clampedValue = max(0, min(partSnapshot.quantityHave, part.quantityNeeded))
                if part.quantityHave != clampedValue {
                    part.quantityHave = clampedValue
                    updatedPartCount += 1
                }
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
                        let baseKey = "\(part.partID.lowercased())|\(part.colorID.lowercased())"
                        let sectionKey = "\(baseKey)|\(part.inventorySection.rawValue.lowercased())"

                        if minifigurePartsLookup[sectionKey] == nil {
                            minifigurePartsLookup[sectionKey] = part
                        }

                        if minifigurePartsLookup[baseKey] == nil {
                            minifigurePartsLookup[baseKey] = part
                        }
                    }

                    for partSnapshot in minifigureSnapshot.parts {
                        guard
                            let key = partSnapshot.lookupKeys.first(where: { minifigurePartsLookup[$0] != nil }),
                            let part = minifigurePartsLookup[key]
                        else {
                            unmatchedPartCount += 1
                            continue
                        }

                        let clampedValue = max(0, min(partSnapshot.quantityHave, part.quantityNeeded))
                        if part.quantityHave != clampedValue {
                            part.quantityHave = clampedValue
                            updatedPartCount += 1
                        }
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
}
