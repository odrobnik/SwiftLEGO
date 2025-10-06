import SwiftUI
import SwiftData

struct ListSidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CollectionList.name, animation: .default) private var lists: [CollectionList]
    @Binding var selection: CollectionList?
    @State private var editorState: EditorState?
    @State private var showingPartSearch = false

    private var listCountDescription: String {
        "\(lists.count) list\(lists.count == 1 ? "" : "s")"
    }

    var body: some View {
        List(selection: $selection) {
            Section("Tools") {
                Button {
                    showingPartSearch = true
                } label: {
                    Label("Find Part", systemImage: "magnifyingglass")
                }
            }

            Section(listCountDescription) {
                ForEach(lists) { list in
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
                    .tag(list)
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
                .onDelete { indexSet in
                    indexSet.map { lists[$0] }.forEach(delete)
                }
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
        .onChange(of: lists.count) { _, newValue in
            guard newValue > 0 else {
                selection = nil
                return
            }

            if selection == nil {
                selection = lists.first
            }
        }
        .sheet(item: $editorState) { state in
            ListEditorView(
                mode: state,
                onSubmit: handleEditorSubmit(_:),
                onDelete: { list in delete(list) }
            )
        }
        .sheet(isPresented: $showingPartSearch) {
            PartSearchView()
        }
    }

    private func delete(_ list: CollectionList) {
        if selection?.persistentModelID == list.persistentModelID {
            selection = nil
        }
        modelContext.delete(list)
        try? modelContext.save()
    }

    private func handleEditorSubmit(_ result: EditorResult) {
        switch result {
        case .created(let name):
            let newList = CollectionList(name: name)
            modelContext.insert(newList)
            selection = newList
        case .renamed(let list, let name):
            list.name = name
            selection = list
        }

        try? modelContext.save()
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
