import Foundation
import SwiftData

public struct InventorySnapshot: Codable, Sendable {
    public struct SetSnapshot: Codable, Sendable {
        public struct PartSnapshot: Codable, Sendable {
            public let partID: String
            public let colorID: String
            public let quantityHave: Int
            public let inventorySection: String?
            public let instanceNumber: Int?
            public let subparts: [PartSnapshot]?

            public init(
                partID: String,
                colorID: String,
                quantityHave: Int,
                inventorySection: String?,
                instanceNumber: Int?,
                subparts: [PartSnapshot]? = nil
            ) {
                self.partID = partID
                self.colorID = colorID
                self.quantityHave = quantityHave
                self.inventorySection = inventorySection
                self.instanceNumber = instanceNumber
                self.subparts = subparts
            }

            private enum CodingKeys: String, CodingKey {
                case partID
                case colorID
                case quantityHave
                case inventorySection
                case instanceNumber
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

        public struct MinifigureSnapshot: Codable, Sendable {
            public let identifier: String
            public let quantityHave: Int
            public let instanceNumber: Int?
            public let parts: [PartSnapshot]

            private enum CodingKeys: String, CodingKey {
                case identifier
                case quantityHave
                case instanceNumber
                case parts
            }

            public init(
                identifier: String,
                quantityHave: Int,
                instanceNumber: Int?,
                parts: [PartSnapshot]
            ) {
                self.identifier = identifier
                self.quantityHave = quantityHave
                self.instanceNumber = instanceNumber
                self.parts = parts
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                identifier = try container.decode(String.self, forKey: .identifier)
                quantityHave = try container.decode(Int.self, forKey: .quantityHave)
                instanceNumber = try container.decodeIfPresent(Int.self, forKey: .instanceNumber)
                parts = try container.decode([PartSnapshot].self, forKey: .parts)
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(identifier, forKey: .identifier)
                try container.encode(quantityHave, forKey: .quantityHave)
                try container.encodeIfPresent(instanceNumber, forKey: .instanceNumber)
                try container.encode(parts, forKey: .parts)
            }
        }

        public let id: UUID?
        public let setNumber: String
        public let name: String?
        public let thumbnailURLString: String?
        public let parts: [PartSnapshot]
        public let minifigures: [MinifigureSnapshot]

        private enum CodingKeys: String, CodingKey {
            case id
            case setNumber
            case name
            case thumbnailURLString
            case parts
            case minifigures
        }

        public init(
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

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id)
            setNumber = try container.decode(String.self, forKey: .setNumber)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            thumbnailURLString = try container.decodeIfPresent(String.self, forKey: .thumbnailURLString)
            parts = try container.decode([PartSnapshot].self, forKey: .parts)
            minifigures = try container.decodeIfPresent([MinifigureSnapshot].self, forKey: .minifigures) ?? []
        }

        public func encode(to encoder: Encoder) throws {
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

    public struct ListSnapshot: Codable, Sendable {
        public let id: UUID?
        public let name: String
        public let sets: [SetSnapshot]

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case sets
        }

        public init(id: UUID? = nil, name: String, sets: [SetSnapshot]) {
            self.id = id
            self.name = name
            self.sets = sets
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            sets = try container.decodeIfPresent([SetSnapshot].self, forKey: .sets) ?? []
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(name, forKey: .name)
            if !sets.isEmpty {
                try container.encode(sets, forKey: .sets)
            }
        }
    }

    public struct ApplyResult: Sendable {
        public let updatedPartCount: Int
        public let matchedSetCount: Int
        public let unmatchedSetNumbers: [String]
        public let unmatchedPartCount: Int

        public var summaryDescription: String {
            var components: [String] = []
            if updatedPartCount > 0 {
                components.append(
                    String(
                        localized: "Updated ^[\(updatedPartCount) part](inflect: true) across ^[\(matchedSetCount) set](inflect: true)"
                    )
                )
            } else if matchedSetCount > 0 {
                components.append(
                    String(
                        localized: "Verified ^[\(matchedSetCount) set](inflect: true); no part quantity changes required"
                    )
                )
            } else {
                components.append(String(localized: "No sets matched the import file"))
            }

            if !unmatchedSetNumbers.isEmpty {
                components.append(
                    String(localized: "Skipped ^[\(unmatchedSetNumbers.count) missing set](inflect: true)")
                )
            }

            if unmatchedPartCount > 0 {
                components.append(
                    String(localized: "Ignored ^[\(unmatchedPartCount) unmatched part](inflect: true)")
                )
            }

            return components.joined(separator: "\n")
        }
    }

    public static let empty = InventorySnapshot(sets: [], lists: [])

    public let sets: [SetSnapshot]
    public let lists: [ListSnapshot]

    private enum CodingKeys: String, CodingKey {
        case sets
        case lists
    }

    public init(sets: [SetSnapshot], lists: [ListSnapshot] = []) {
        self.sets = sets
        self.lists = lists
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sets = try container.decodeIfPresent([SetSnapshot].self, forKey: .sets) ?? []
        lists = try container.decodeIfPresent([ListSnapshot].self, forKey: .lists) ?? []
    }

    public func encode(to encoder: Encoder) throws {
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
    public static func make(from lists: [CollectionList]) -> InventorySnapshot {
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
    public func apply(to lists: [CollectionList]) -> ApplyResult {
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

            let partsLookup = makePartLookup(from: set.parts)

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
                var minifigureLookup: [String: [Minifigure]] = [:]
                for minifigure in set.minifigures {
                    let key = minifigure.identifier.lowercased()
                    minifigureLookup[key, default: []].append(minifigure)
                }

                for key in minifigureLookup.keys {
                    minifigureLookup[key]?.sort { $0.instanceNumber < $1.instanceNumber }
                }

                for minifigureSnapshot in setSnapshot.minifigures {
                    let identifierKey = minifigureSnapshot.identifier.lowercased()
                    guard let candidates = minifigureLookup[identifierKey], !candidates.isEmpty else {
                        unmatchedPartCount += 1
                        continue
                    }

                    let targetMinifigure: Minifigure
                    if let snapshotInstance = minifigureSnapshot.instanceNumber,
                       let match = candidates.first(where: { $0.instanceNumber == snapshotInstance }) {
                        targetMinifigure = match
                    } else if let fallback = candidates.first {
                        targetMinifigure = fallback
                    } else {
                        unmatchedPartCount += 1
                        continue
                    }

                    let clampedQuantity = max(0, min(minifigureSnapshot.quantityHave, targetMinifigure.quantityNeeded))
                    if targetMinifigure.quantityHave != clampedQuantity {
                        targetMinifigure.quantityHave = clampedQuantity
                        updatedPartCount += 1
                    }

                    let minifigurePartsLookup = makePartLookup(from: targetMinifigure.parts)

                    for partSnapshot in minifigureSnapshot.parts {
                        applyPartSnapshot(
                            partSnapshot,
                            parts: targetMinifigure.parts,
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
                instanceNumber: part.instanceNumber,
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
        if lhsSection.caseInsensitiveCompare(rhsSection) != .orderedSame {
            return lhsSection.localizedCaseInsensitiveCompare(rhsSection) == .orderedAscending
        }

        let lhsInstance = lhs.instanceNumber ?? 0
        let rhsInstance = rhs.instanceNumber ?? 0
        if lhsInstance != rhsInstance {
            return lhsInstance < rhsInstance
        }

        return lhs.quantityHave < rhs.quantityHave
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
                instanceNumber: part.instanceNumber,
                subparts: makePartSnapshots(from: part.subparts)
            )
        }
        .sorted(by: partSnapshotSortComparator)

        let minifigureSnapshots = set.minifigures
            .sorted {
                let identifierComparison = $0.identifier.localizedCaseInsensitiveCompare($1.identifier)
                if identifierComparison != .orderedSame {
                    return identifierComparison == .orderedAscending
                }

                if $0.instanceNumber != $1.instanceNumber {
                    return $0.instanceNumber < $1.instanceNumber
                }

                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            .map { minifigure in
                let componentParts = minifigure.parts.map { part in
                    SetSnapshot.PartSnapshot(
                        partID: part.partID,
                        colorID: part.colorID,
                        quantityHave: part.quantityHave,
                        inventorySection: part.inventorySection.rawValue,
                        instanceNumber: part.instanceNumber,
                        subparts: makePartSnapshots(from: part.subparts)
                    )
                }
                .sorted(by: partSnapshotSortComparator)

                return SetSnapshot.MinifigureSnapshot(
                    identifier: minifigure.identifier,
                    quantityHave: minifigure.quantityHave,
                    instanceNumber: minifigure.instanceNumber,
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
        precomputedLookup: [String: [Part]]? = nil,
        updatedPartCount: inout Int,
        unmatchedPartCount: inout Int
    ) {
        let lookup = precomputedLookup ?? makePartLookup(from: parts)

        guard let key = snapshot.lookupKeys.first(where: { (lookup[$0]?.isEmpty == false) }) else {
            unmatchedPartCount += 1
            return
        }

        guard let candidates = lookup[key], !candidates.isEmpty else {
            unmatchedPartCount += 1
            return
        }

        let part: Part
        if let snapshotInstance = snapshot.instanceNumber,
           let match = candidates.first(where: { $0.instanceNumber == snapshotInstance }) {
            part = match
        } else {
            part = candidates.first!
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

    private func makePartLookup(from parts: [Part]) -> [String: [Part]] {
        var lookup: [String: [Part]] = [:]
        for part in parts {
            insertPart(part, into: &lookup)
        }

        for key in lookup.keys {
            lookup[key]?.sort { $0.instanceNumber < $1.instanceNumber }
        }

        return lookup
    }

    private func insertPart(_ part: Part, into lookup: inout [String: [Part]]) {
        let baseKey = "\(part.partID.lowercased())|\(part.colorID.lowercased())"
        let sectionKey = "\(baseKey)|\(part.inventorySection.rawValue.lowercased())"

        lookup[sectionKey, default: []].append(part)
        lookup[baseKey, default: []].append(part)
    }
}

extension InventorySnapshot.SetSnapshot {
    fileprivate func matches(_ set: BrickSet) -> Bool {
        if let snapshotID = id, snapshotID == set.id {
            return true
        }

        return setNumber.localizedCaseInsensitiveCompare(set.setNumber) == .orderedSame
    }
}

extension InventorySnapshot {
    @MainActor
    public static func snapshot(for set: BrickSet, in list: CollectionList) -> SetSnapshot? {
        let inventorySnapshot = make(from: [list])
        return inventorySnapshot.sets.first { $0.matches(set) }
    }
}
