import SwiftUI
import SwiftData
import BrickCore

/// The results of a set grid search in the selected scope.
struct SetSearchResults: View {
    let search: SetInventorySearch
    let source: SetGridSource

    var body: some View {
        switch search.scope {
        case .sets:
            SetSearchResultsGrid(source: source, query: search.effectiveQuery)
        case .parts:
            PartSearchResultsList(entries: search.partResults, query: search.effectiveQuery)
        case .minifigures:
            MinifigureSearchResultsList(entries: search.minifigureResults, query: search.effectiveQuery)
        }
    }
}

/// The sets matching a search, grouped by category.
private struct SetSearchResultsGrid: View {
    let source: SetGridSource
    let query: String

    var body: some View {
        let sections = SetSection.byCategory(SetInventorySearch.sets(matching: query, in: source.sets))

        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if sections.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .padding()
                } else {
                    ForEach(sections) { section in
                        SetCategorySection(section: section)
                    }
                }
            }
            .padding(.top, 16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

/// Parts matching a search that are still missing, grouped by colour.
private struct PartSearchResultsList: View {
    let entries: [PartSearchEntry]
    let query: String

    var body: some View {
        // Filtered here rather than when searching so that a part completed in the set
        // screen is gone when navigating back.
        let groups = Self.colorGroups(of: entries.filter { $0.missingCount > 0 })

        List {
            if groups.isEmpty {
                ContentUnavailableView.search(text: query)
                    .padding()
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(groups, id: \.colorName) { group in
                    Section(group.colorName) {
                        ForEach(group.entries) { entry in
                            NavigationLink(value: entry.searchResult) {
                                PartSearchResultRow(
                                    set: entry.set,
                                    part: entry.part,
                                    owningMinifigure: entry.owningMinifigure,
                                    parentChain: entry.parentChain
                                )
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private static func colorGroups(of entries: [PartSearchEntry]) -> [(colorName: String, entries: [PartSearchEntry])] {
        Dictionary(grouping: entries, by: \.groupingColorName)
            .map { colorName, entries in
                let sortedEntries = entries.sorted { lhs, rhs in
                    let nameComparison = lhs.part.name.localizedCaseInsensitiveCompare(rhs.part.name)
                    if nameComparison != .orderedSame {
                        return nameComparison == .orderedAscending
                    }
                    return lhs.part.partID.localizedCaseInsensitiveCompare(rhs.part.partID) == .orderedAscending
                }
                return (colorName: colorName, entries: sortedEntries)
            }
            .sorted { lhs, rhs in
                lhs.colorName.localizedCaseInsensitiveCompare(rhs.colorName) == .orderedAscending
            }
    }
}

/// Minifigures matching a search.
private struct MinifigureSearchResultsList: View {
    let entries: [MinifigureSearchEntry]
    let query: String

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView.search(text: query)
                    .padding()
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(entries) { entry in
                    NavigationLink(value: entry.searchResult) {
                        MinifigureSearchResultRow(set: entry.set, minifigure: entry.minifigure)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
