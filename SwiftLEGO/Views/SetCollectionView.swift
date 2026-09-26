import SwiftUI
import SwiftData
import BrickCore

struct SetCollectionView: View {
    let list: CollectionList
    @State private var search = SetInventorySearch()
    @State private var gridModel = SetGridModel()
    @State private var showingAddSetSheet = false
    @State private var showingBulkAddSheet = false
    @State private var wantedListDocument = WantedListDocument(inventory: .empty)
    @State private var wantedListFilename = WantedListDocument.defaultFilename()
    @State private var isExportingWantedList = false

    var body: some View {
        Group {
            if search.isSearching {
                SetSearchResults(search: search, source: .list(list))
            } else {
                CollectionSetGrid(list: list)
            }
        }
        .navigationTitle(list.name)
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
            await search.run(search.taskKey, in: list.sets)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingAddSetSheet = true
                    } label: {
                        Label("Add Single Set", systemImage: "plus")
                    }

                    Button {
                        showingBulkAddSheet = true
                    } label: {
                        Label("Bulk Add from File", systemImage: "tray.and.arrow.down.fill")
                    }
                } label: {
                    Label("Add Sets", systemImage: "plus")
                }
            }

            ToolbarItem(placement: .secondaryAction) {
                Button {
                    beginWantedListExport()
                } label: {
                    Label("Export Wanted List", systemImage: "square.and.arrow.up.on.square")
                }
                .disabled(list.sets.isEmpty)
            }
        }
        .sheet(isPresented: $showingAddSetSheet) {
            AddSetView(list: list)
        }
        .sheet(isPresented: $showingBulkAddSheet) {
            BulkAddSetsView(list: list)
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
    }

    private func beginWantedListExport() {
        guard !list.sets.isEmpty else { return }
        let inventory = WantedListExporter.makeInventory(from: list.sets.sorted(by: BrickSet.displayOrder))
        wantedListDocument = WantedListDocument(inventory: inventory)
        wantedListFilename = WantedListDocument.defaultFilename()
        isExportingWantedList = true
    }
}

/// The sets of a collection list, grouped by category.
private struct CollectionSetGrid: View {
    let list: CollectionList

    var body: some View {
        let sections = SetSection.byCategory(list.sets)

        ScrollView {
            if sections.isEmpty {
                EmptyStateView(
                    icon: "shippingbox",
                    title: "No Sets Yet",
                    message: "Add a BrickLink set to this list to start tracking its parts."
                )
                .padding(.top, 80)
            } else {
                SetSectionStack(sections: sections)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

#Preview("Sets Grid") {
    let container = SwiftLEGOModelContainer.preview
    let list = try! ModelContext(container)
        .fetch(FetchDescriptor<CollectionList>())
        .first!

    return NavigationStack {
        SetCollectionView(list: list)
    }
    .modelContainer(container)
}
