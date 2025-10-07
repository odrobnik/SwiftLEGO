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

        let setNumber: String
        let parts: [PartSnapshot]
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
                SetSnapshot(
                    setNumber: set.setNumber,
                    parts: set.parts.map { part in
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
