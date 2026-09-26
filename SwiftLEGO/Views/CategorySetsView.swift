import SwiftUI
import SwiftData
import BrickCore

struct CategorySetsView: View {
    let categoryPath: [String]
    let sets: [BrickSet]
    @State private var search = SetInventorySearch()
    @State private var gridModel = SetGridModel()
    @State private var wantedListDocument = WantedListDocument(inventory: .empty)
    @State private var wantedListFilename = WantedListDocument.defaultFilename()
    @State private var isExportingWantedList = false

    var body: some View {
        Group {
            if search.isSearching {
                SetSearchResults(search: search, source: .sets(sets))
            } else {
                CategorySetGrid(categoryPath: categoryPath, sets: sets)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(categoryPath.joined(separator: " / "))
        .searchable(
            text: $search.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(search.scope.prompt)
        )
        .searchScopes($search.scope, activation: .onSearchPresentation) {
            ForEach(SetInventorySearch.Scope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .task(id: search.taskKey) {
            await search.run(search.taskKey, in: sets)
        }
        .setGridPresentations(for: gridModel)
        .fileExporter(
            isPresented: $isExportingWantedList,
            document: wantedListDocument,
            contentType: .brickLinkWantedList,
            defaultFilename: wantedListFilename
        ) { result in
            if case .failure(let error) = result {
                gridModel.alert = SetGridModel.AlertMessage(
                    title: "Export Failed",
                    message: "Wanted list export failed: \(error.localizedDescription)"
                )
            }
        }
        .quickLookPresenter()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    beginWantedListExport()
                } label: {
                    Label("Export Wanted List", systemImage: "square.and.arrow.up.on.square")
                }
                .disabled(sets.isEmpty)
            }
        }
    }

    private func beginWantedListExport() {
        guard !sets.isEmpty else { return }
        let inventory = WantedListExporter.makeInventory(from: sets)
        wantedListDocument = WantedListDocument(inventory: inventory)
        wantedListFilename = WantedListDocument.defaultFilename()
        isExportingWantedList = true
    }
}

/// The sets of a category, grouped by their subcategories.
private struct CategorySetGrid: View {
    let categoryPath: [String]
    let sets: [BrickSet]

    var body: some View {
        let sections = SetSection.byCategory(sets, below: categoryPath)

        ScrollView {
            if sections.isEmpty {
                EmptyStateView(
                    icon: "shippingbox",
                    title: "No Sets Found",
                    message: "No sets are tagged with this category."
                )
                .padding(.top, 80)
            } else {
                SetSectionStack(sections: sections)
            }
        }
    }
}
