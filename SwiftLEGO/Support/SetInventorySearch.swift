import Foundation
import SwiftData
import BrickCore

/// The search of a set grid: the scope and text typed into the search field, the
/// debounced query that results are shown for, and the part and minifigure results.
@MainActor
@Observable
final class SetInventorySearch {
    enum Scope: String, CaseIterable, Identifiable {
        case sets
        case parts
        case minifigures

        var id: Scope { self }

        var title: String { rawValue.capitalized }

        var prompt: String { "Search \(rawValue)" }
    }

    struct TaskKey: Equatable {
        let query: String
        let scope: Scope
    }

    var query = ""
    var scope: Scope = .sets
    /// The trimmed query that the results belong to; empty while not searching.
    private(set) var effectiveQuery = ""
    private(set) var partResults: [PartSearchEntry] = []
    private(set) var minifigureResults: [MinifigureSearchEntry] = []

    var taskKey: TaskKey {
        TaskKey(query: query, scope: scope)
    }

    var isSearching: Bool {
        !effectiveQuery.isEmpty
    }

    /// Debounces `key`, then searches `sets`. Run it from `.task(id: taskKey)` so a new
    /// keystroke cancels the previous search.
    func run(_ key: TaskKey, in sets: [BrickSet]) async {
        let trimmed = key.query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            effectiveQuery = ""
            partResults = []
            minifigureResults = []
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return
        }

        guard !Task.isCancelled else { return }

        effectiveQuery = trimmed
        switch key.scope {
        case .parts:
            partResults = Self.partEntries(matching: trimmed, in: sets)
            minifigureResults = []
        case .minifigures:
            minifigureResults = Self.minifigureEntries(matching: trimmed, in: sets)
            partResults = []
        case .sets:
            partResults = []
            minifigureResults = []
        }
    }

    /// The sets whose number or name matches `query`.
    static func sets(matching query: String, in sets: [BrickSet]) -> [BrickSet] {
        let normalizedQuery = SearchText.normalized(query)
        let strippedQuery = SearchText.strippedSetNumber(normalizedQuery)
        let tokens = SearchText.tokens(from: query)

        return sets.filter { set in
            let setNumber = SearchText.normalized(set.setNumber)
            if !normalizedQuery.isEmpty {
                if setNumber == normalizedQuery {
                    return true
                }

                if !strippedQuery.isEmpty && SearchText.strippedSetNumber(setNumber) == strippedQuery {
                    return true
                }
            }

            return SearchText.matches(nameTokens: tokens, in: set.name)
        }
    }

    private static func partEntries(matching query: String, in sets: [BrickSet]) -> [PartSearchEntry] {
        guard let partQuery = PartSearchQuery(query) else { return [] }

        var entries: [PersistentIdentifier: PartSearchEntry] = [:]
        var matchOrder = 0

        for set in sets.sorted(by: BrickSet.displayOrder) {
            enumerateSearchableParts(in: set) { part, owningMinifigure in
                guard partQuery.matches(partID: part.partID, colorName: part.colorName, name: part.name),
                      part.missingQuantity > 0 else {
                    return
                }

                let key = part.persistentModelID
                if entries[key] == nil {
                    entries[key] = PartSearchEntry(
                        set: part.set ?? part.minifigure?.set ?? set,
                        part: part,
                        owningMinifigure: owningMinifigure,
                        parentChain: parentChain(for: part),
                        searchQuery: query,
                        orderIndex: matchOrder
                    )
                }

                matchOrder += 1
            }
        }

        return entries.values.sorted { lhs, rhs in
            if lhs.orderIndex != rhs.orderIndex {
                return lhs.orderIndex < rhs.orderIndex
            }
            return lhs.part.partID.localizedCaseInsensitiveCompare(rhs.part.partID) == .orderedAscending
        }
    }

    private static func minifigureEntries(matching query: String, in sets: [BrickSet]) -> [MinifigureSearchEntry] {
        let normalizedQuery = SearchText.normalized(query)
        guard !normalizedQuery.isEmpty else { return [] }
        let tokens = SearchText.tokens(from: query)

        return sets
            .flatMap(\.minifigures)
            .compactMap { minifigure in
                let matchesIdentifier = SearchText.normalized(minifigure.identifier) == normalizedQuery
                guard matchesIdentifier || SearchText.matches(nameTokens: tokens, in: minifigure.name),
                      let set = minifigure.set else {
                    return nil
                }
                return MinifigureSearchEntry(set: set, minifigure: minifigure, searchQuery: query)
            }
            .sorted { lhs, rhs in
                if lhs.missingCount != rhs.missingCount {
                    return lhs.missingCount < rhs.missingCount
                }
                return lhs.minifigure.identifier.localizedCaseInsensitiveCompare(rhs.minifigure.identifier) == .orderedAscending
            }
    }

    /// Visits the parts of `set` a part search can return: incomplete, non-extra parts,
    /// descending into an assembly only when some of it is already owned.
    private static func enumerateSearchableParts(
        in set: BrickSet,
        visit: (Part, Minifigure?) -> Void
    ) {
        func walk(_ part: Part, owningMinifigure: Minifigure?) {
            guard part.inventorySection != .extra else { return }

            let isComplete = part.quantityNeeded > 0 && part.quantityHave >= part.quantityNeeded
            guard !isComplete else { return }

            let hasProgress = part.hasOwnedQuantityInHierarchy()
            let hasUniformMissingSubparts = part.hasUniformMissingSubparts()

            if part.subparts.isEmpty || !hasProgress || hasUniformMissingSubparts {
                visit(part, owningMinifigure)
            }

            guard hasProgress, !hasUniformMissingSubparts else { return }

            for child in part.subparts {
                walk(child, owningMinifigure: owningMinifigure)
            }
        }

        for part in set.parts {
            walk(part, owningMinifigure: nil)
        }

        for minifigure in set.minifigures {
            for part in minifigure.parts {
                walk(part, owningMinifigure: minifigure)
            }
        }
    }

    private static func parentChain(for part: Part) -> [Part] {
        var chain: [Part] = []
        var current = part.parentPart

        while let node = current {
            chain.append(node)
            current = node.parentPart
        }

        return chain.reversed()
    }
}

/// A part found by a part search, with where it sits in its set.
struct PartSearchEntry: Identifiable, Equatable {
    let set: BrickSet
    let part: Part
    let owningMinifigure: Minifigure?
    let parentChain: [Part]
    /// The query the part was found with; opening the result filters the set by it.
    let searchQuery: String
    let orderIndex: Int

    var id: PersistentIdentifier { part.persistentModelID }

    var missingCount: Int {
        max(part.quantityNeeded - part.quantityHave, 0)
    }

    var groupingColorName: String {
        part.colorName.isEmpty ? "Unknown Color" : part.colorName
    }

    var searchResult: SearchResult {
        SearchResult(set: set, searchQuery: searchQuery, section: part.inventorySection)
    }
}

/// A minifigure found by a minifigure search.
struct MinifigureSearchEntry: Identifiable, Equatable {
    let set: BrickSet
    let minifigure: Minifigure
    /// The query the minifigure was found with; opening the result filters the set by it.
    let searchQuery: String

    var id: PersistentIdentifier { minifigure.persistentModelID }

    var missingCount: Int {
        max(minifigure.quantityNeeded - minifigure.quantityHave, 0)
    }

    var searchResult: SearchResult {
        SearchResult(set: set, searchQuery: searchQuery, section: .regular)
    }
}

extension BrickSet {
    /// Orders sets by set number, then by name.
    static func displayOrder(_ lhs: BrickSet, _ rhs: BrickSet) -> Bool {
        if lhs.setNumber != rhs.setNumber {
            return lhs.setNumber < rhs.setNumber
        }
        return lhs.name < rhs.name
    }
}
