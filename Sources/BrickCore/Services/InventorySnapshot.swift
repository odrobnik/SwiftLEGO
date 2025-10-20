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

        let id: UUID?
        let setNumber: String
        let name: String?
        let thumbnailURLString: String?
        let parts: [PartSnapshot]
        let minifigures: [MinifigureSnapshot]

        private enum CodingKeys: String, CodingKey {
            case id
            case setNumber
            case name
            case thumbnailURLString
            case parts
            case minifigures
        }

        init(
            id: UUID? = nil,
            setNumber: String,
            name: String? = nil,
            thumbnailURLString: String? = nil,
            parts: [PartSnapshot],
            minifigures: [MinifigureSnapshot] = []
        ) {
            self.id = id
            self.setNumber = setNumber
            self.name = name
            self.thumbnailURLString = thumbnailURLString
            self.parts = parts
            self.minifigures = minifigures
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id)
            setNumber = try container.decode(String.self, forKey: .setNumber)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            thumbnailURLString = try container.decodeIfPresent(String.self, forKey: .thumbnailURLString)
            parts = try container.decode([PartSnapshot].self, forKey: .parts)
            minifigures = try container.decodeIfPresent([MinifigureSnapshot].self, forKey: .minifigures) ?? []
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(setNumber, forKey: .setNumber)
            if let name, !name.isEmpty {
                try container.encode(name, forKey: .name)
            }
            if let thumbnailURLString, !thumbnailURLString.isEmpty {
                try container.encode(thumbnailURLString, forKey: .thumbnailURLString)
            }
            try container.encode(parts, forKey: .parts)
            if !minifigures.isEmpty {
                try container.encode(minifigures, forKey: .minifigures)
            }
        }
    }

    struct ListSnapshot: Codable, Sendable {
        let id: UUID?
        let name: String
        let sets: [SetSnapshot]

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case sets
        }

        init(id: UUID? = nil, name: String, sets: [SetSnapshot]) {
            self.id = id
            self.name = name
            self.sets = sets
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            sets = try container.decodeIfPresent([SetSnapshot].self, forKey: .sets) ?? []
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(name, forKey: .name)
            if !sets.isEmpty {
                try container.encode(sets, forKey: .sets)
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
            if updatedPartCount > 0 {
                components.append("Updated \(updatedPartCount) part\(updatedPartCount == 1 ? "" : "s") across \(matchedSetCount) set\(matchedSetCount == 1 ? "" : "s")")
            } else if matchedSetCount > 0 {
                components.append("Verified \(matchedSetCount) set\(matchedSetCount == 1 ? "" : "s"); no part quantity changes required")
            } else {
                components.append("No sets matched the import file")
            }

            if !unmatchedSetNumbers.isEmpty {
                components.append("Skipped \(unmatchedSetNumbers.count) missing set\(unmatchedSetNumbers.count == 1 ? "" : "s")")
            }

            if unmatchedPartCount > 0 {
                components.append("Ignored \(unmatchedPartCount) unmatched part\(unmatchedPartCount == 1 ? "" : "s")")
            }

            return components.joined(separator: "\n")
        }
    }

    static let empty = InventorySnapshot(sets: [], lists: [])

    let sets: [SetSnapshot]
    let lists: [ListSnapshot]

    private enum CodingKeys: String, CodingKey {
        case sets
        case lists
    }

    init(sets: [SetSnapshot], lists: [ListSnapshot] = []) {
        self.sets = sets
        self.lists = lists
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sets = try container.decodeIfPresent([SetSnapshot].self, forKey: .sets) ?? []
        lists = try container.decodeIfPresent([ListSnapshot].self, forKey: .lists) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !sets.isEmpty {
            try container.encode(sets, forKey: .sets)
        }
        if !lists.isEmpty {
            try container.encode(lists, forKey: .lists)
        }
    }
}

extension InventorySnapshot {
    @MainActor
    static func make(from lists: [CollectionList]) -> InventorySnapshot {
        let allSets = lists
            .flatMap { $0.sets }
            .sorted(by: setSortComparator)
            .map { makeSetSnapshot(from: $0) }

        let listSnapshots = lists.map { list in
            let listSets = list.sets
                .sorted(by: setSortComparator)
                .map { makeSetSnapshot(from: $0) }
            return ListSnapshot(id: list.id, name: list.name, sets: listSets)
        }

        return InventorySnapshot(sets: allSets, lists: listSnapshots)
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

        let resolvedSnapshots = !sets.isEmpty ? sets : self.lists.flatMap { $0.sets }

        for setSnapshot in resolvedSnapshots {
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

    private static func setSortComparator(_ lhs: BrickSet, _ rhs: BrickSet) -> Bool {
        if lhs.setNumber.caseInsensitiveCompare(rhs.setNumber) != .orderedSame {
            return lhs.setNumber.localizedCaseInsensitiveCompare(rhs.setNumber) == .orderedAscending
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private static func makeSetSnapshot(from set: BrickSet) -> SetSnapshot {
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
            id: set.id,
            setNumber: set.setNumber,
            name: set.name,
            thumbnailURLString: set.thumbnailURLString,
            parts: partSnapshots,
            minifigures: minifigureSnapshots
        )
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
