import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CollectionList.name, animation: .default) private var lists: [CollectionList]
    @State private var path: [Destination] = []
    @State private var selectedListID: PersistentIdentifier?

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.automatic)) {
            ListSidebarView(
                selectionID: bindingSelectedListID,
                onSetSelected: handleSidebarSetSelection(_:),
                selectedSetID: currentSelectedSetID
            )
                .background(Color(uiColor: .systemGroupedBackground))
        } detail: {
            NavigationStack(path: $path) {
                Group {
                    if let list = selectedList {
                        SetCollectionView(list: list) { destination in
                            path.append(destination)
                        }
                        .id(list.persistentModelID)
                    } else if let first = lists.first {
                        SetCollectionView(list: first) { destination in
                            path.append(destination)
                        }
                        .task { setSelectedList(first) }
                    } else {
                        EmptyStateView(
                            icon: "square.stack.3d.up.slash",
                            title: "No Lists Yet",
                            message: "Create a list to start organizing your LEGO sets."
                        )
                    }
                }
                .navigationDestination(for: Destination.self, destination: makeDestination)
            }
        }
        .onChange(of: lists.count) { _, _ in
            ensureSelection()
        }
        .task {
            ensureSelection()
        }
    }
    
    private var bindingSelectedListID: Binding<PersistentIdentifier?> {
        Binding(get: { selectedListID }, set: { newID in
            selectedListID = newID
        })
    }
    
    private var selectedList: CollectionList? {
        guard let selectedListID else { return nil }
        return lists.first(where: { $0.persistentModelID == selectedListID })
    }
    
    private func ensureSelection() {
        if selectedListID == nil {
            setSelectedList(lists.first)
        } else if selectedList == nil {
            setSelectedList(lists.first)
        }
    }
    
    private func setSelectedList(_ list: CollectionList?) {
        selectedListID = list?.persistentModelID
    }

    private var currentSelectedSetID: PersistentIdentifier? {
        switch path.last {
        case .set(let id):
            return id
        case .filteredSet(let id, _):
            return id
        case .none:
            return nil
        }
    }

    private func handleSidebarSetSelection(_ set: BrickSet) {
        guard let list = set.collection else { return }
        setSelectedList(list)
        path = [.set(set.persistentModelID)]
    }
    
    @ViewBuilder
    private func makeDestination(_ destination: Destination) -> some View {
        switch destination {
        case .set(let setID):
            if let set = fetchSet(with: setID) {
                SetDetailView(brickSet: set)
            } else {
                Text("Set unavailable")
                    .foregroundStyle(.secondary)
            }
        case .filteredSet(let setID, let partID):
            if let set = fetchSet(with: setID) {
                SetDetailView(brickSet: set) { part in
                    part.partID.compare(partID, options: .caseInsensitive) == .orderedSame
                }
            } else {
                Text("Set unavailable")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func fetchSet(with id: PersistentIdentifier) -> BrickSet? {
        for list in lists {
            if let match = list.sets.first(where: { $0.persistentModelID == id }) {
                return match
            }
        }
        return nil
    }
}

extension ContentView {
    enum Destination: Hashable {
        case set(PersistentIdentifier)
        case filteredSet(PersistentIdentifier, partID: String)
    }
}

#Preview("App Root") {
    ContentView()
        .modelContainer(SwiftLEGOModelContainer.preview)
}
