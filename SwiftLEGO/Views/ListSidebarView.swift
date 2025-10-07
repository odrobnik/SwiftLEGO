import SwiftUI
import SwiftData

struct ListSidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CollectionList.name, animation: .default) private var lists: [CollectionList]
    @Binding var selectionID: PersistentIdentifier?
    @State private var editorState: EditorState?
    @State private var expandedLists: Set<PersistentIdentifier> = []
    @State private var setBeingRenamed: BrickSet?
    let onSetSelected: (BrickSet) -> Void
    let selectedSetID: PersistentIdentifier?

    private var listCountDescription: String {
        "\(lists.count) list\(lists.count == 1 ? "" : "s")"
    }

    var body: some View {
        List(selection: $selectionID) {
            if !lists.isEmpty {
                Section {
                    Text(listCountDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(lists) { list in
                Section(isExpanded: binding(for: list)) {
                    let sets = sortedSets(for: list)
                    if sets.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "tray")
                                .foregroundStyle(.secondary)
                            Text("No sets yet")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.leading, 28)
                        .padding(.vertical, 6)
                    } else {
                        ForEach(sets) { set in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Image(systemName: "shippingbox")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(set.name)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Text(set.setNumber)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.leading, 28)
                            .padding(.vertical, 4)
                            .background(selectionHighlight(for: set))
                            .onTapGesture {
                                handleSetSelection(set, in: list)
                            }
                            .contextMenu {
                                Button("Rename", systemImage: "pencil") {
                                    setBeingRenamed = set
                                }
                                Button(role: .destructive) {
                                    deleteSet(set)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    listHeader(for: list)
                }
                .listRowBackground(Color.clear)
            }
            .onDelete { indexSet in
                indexSet.map { lists[$0] }.forEach(delete)
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorState = .create
                } label: {
                    Label("Add List", systemImage: "plus")
                }
            }
        }
        .overlay {
            if lists.isEmpty {
                EmptyStateView(
                    icon: "square.stack.3d.up",
                    title: "Create Your First List",
                    message: "Lists help you group LEGO sets by lot, collection, or theme."
                )
                .padding()
            }
        }
        .onChange(of: lists.count) { _, _ in
            ensureSelection()
        }
        .onChange(of: lists.map(\.persistentModelID)) { _, newIDs in
            expandedLists = expandedLists.filter { newIDs.contains($0) }
        }
        .sheet(item: $editorState) { state in
            ListEditorView(
                mode: state,
                onSubmit: handleEditorSubmit(_:),
                onDelete: { list in delete(list) }
            )
        }
        .sheet(item: $setBeingRenamed) { set in
            RenameSetView(set: set)
        }
    }

    private func delete(_ list: CollectionList) {
        if selectionID == list.persistentModelID {
            selectionID = nil
        }
        expandedLists.remove(list.persistentModelID)
        modelContext.delete(list)
        try? modelContext.save()
        ensureSelection()
    }

    private func handleEditorSubmit(_ result: EditorResult) {
        switch result {
        case .created(let name):
            let newList = CollectionList(name: name)
            modelContext.insert(newList)
            selectionID = newList.persistentModelID
        case .renamed(let list, let name):
            list.name = name
            selectionID = list.persistentModelID
        }

        try? modelContext.save()
    }

    private func ensureSelection() {
        guard !lists.isEmpty else {
            selectionID = nil
            return
        }

        if selectionID == nil {
            selectionID = lists.first?.persistentModelID
        }
    }

    private func binding(for list: CollectionList) -> Binding<Bool> {
        let id = list.persistentModelID
        return Binding(
            get: { expandedLists.contains(id) },
            set: { newValue in
                if newValue {
                    expandedLists.insert(id)
                } else {
                    expandedLists.remove(id)
                }
            }
        )
    }

    private func sortedSets(for list: CollectionList) -> [BrickSet] {
        list.sets.sorted { lhs, rhs in
            if lhs.setNumber == rhs.setNumber {
                return lhs.name < rhs.name
            }
            return lhs.setNumber < rhs.setNumber
        }
    }

    private func listHeader(for list: CollectionList) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(list.name)
                    .font(.headline)
                Text("\(list.sets.count) sets")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "square.stack.3d.up")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .simultaneousGesture(
            TapGesture().onEnded {
                selectionID = list.persistentModelID
            }
        )
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                editorState = .rename(list)
            }
            Button(role: .destructive) {
                delete(list)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Rename") {
                editorState = .rename(list)
            }
            .tint(.blue)

            Button(role: .destructive) {
                delete(list)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func handleSetSelection(_ set: BrickSet, in list: CollectionList) {
        selectionID = list.persistentModelID
        onSetSelected(set)
    }

    private func deleteSet(_ set: BrickSet) {
        modelContext.delete(set)
        try? modelContext.save()
    }

    @ViewBuilder
    private func selectionHighlight(for set: BrickSet) -> some View {
        if let selectedSetID, set.persistentModelID == selectedSetID {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .padding(.leading, -12)
        } else {
            EmptyView()
        }
    }
}

// MARK: - Editor Support

enum EditorResult {
    case created(String)
    case renamed(CollectionList, String)
}

enum EditorState: Identifiable {
    case create
    case rename(CollectionList)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .rename(let list):
            return "rename-\(list.id.uuidString)"
        }
    }
}
