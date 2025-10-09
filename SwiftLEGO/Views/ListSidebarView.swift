import SwiftUI
import SwiftData

struct ListSidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CollectionList.name, animation: .default) private var lists: [CollectionList]
    @Binding var selectionID: PersistentIdentifier?
    @Binding var selectedCategoryPath: [String]?
    @State private var editorState: EditorState?
    @State private var expandedLists: Set<PersistentIdentifier> = []
    @State private var expandedCategoryIDs: Set<String> = []
    @State private var setBeingRenamed: BrickSet?
    let onSetSelected: (BrickSet) -> Void
    let onCategorySelected: ([String]?) -> Void
    let selectedSetID: PersistentIdentifier?

    private var listCountDescription: String {
        "\(lists.count) list\(lists.count == 1 ? "" : "s")"
    }
    private let uncategorizedCategoryTitle = "Uncategorized"

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

            if !categoryNodes.isEmpty {
                Section("Categories") {
                    ForEach(categoryNodes) { node in
                        categoryTreeRow(for: node, level: 0)
                    }
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
        .onChange(of: selectedCategoryPath) { _, newValue in
            if let path = newValue {
                expandAncestors(of: path)
            }
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
        if lists.isEmpty {
            selectedCategoryPath = nil
            onCategorySelected(nil)
        }
    }

    private func handleEditorSubmit(_ result: EditorResult) {
        switch result {
        case .created(let name):
            let newList = CollectionList(name: name)
            modelContext.insert(newList)
            selectionID = newList.persistentModelID
            selectedCategoryPath = nil
            onCategorySelected(nil)
        case .renamed(let list, let name):
            list.name = name
            selectionID = list.persistentModelID
            selectedCategoryPath = nil
            onCategorySelected(nil)
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

    private var categoryNodes: [CategoryNode] {
        let allSets = lists.flatMap { $0.sets }
        guard !allSets.isEmpty else { return [] }

        var nodesByID: [String: MutableCategoryNode] = [:]
        var rootNodes: [MutableCategoryNode] = []

        for set in allSets {
            let path = set.normalizedCategoryPath(uncategorizedTitle: uncategorizedCategoryTitle)
            guard !path.isEmpty else { continue }

            var parentNode: MutableCategoryNode?

            for depth in 0..<path.count {
                let currentPath = Array(path.prefix(depth + 1))
                let id = categoryID(for: currentPath)

                let node: MutableCategoryNode
                if let existing = nodesByID[id] {
                    node = existing
                } else {
                    node = MutableCategoryNode(name: currentPath.last ?? "", path: currentPath)
                    nodesByID[id] = node

                    if let parent = parentNode {
                        parent.children.append(node)
                    } else {
                        rootNodes.append(node)
                    }
                }

                node.setIDs.insert(set.persistentModelID)
                parentNode = node
            }
        }

        func convert(_ node: MutableCategoryNode) -> CategoryNode {
            let children = node.children
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map(convert)

            return CategoryNode(
                id: categoryID(for: node.path),
                name: node.name,
                path: node.path,
                setIDs: node.setIDs,
                children: children
            )
        }

        return rootNodes
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map(convert)
    }

    @ViewBuilder
    private func categoryTreeRow(for node: CategoryNode, level: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                if node.children.isEmpty {
                    Color.clear
                        .frame(width: 24, height: 24)
                } else {
                    Button {
                        toggleCategoryExpansion(node)
                    } label: {
                        Image(systemName: isCategoryExpanded(node) ? "chevron.down" : "chevron.right")
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    selectCategory(node)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: node.children.isEmpty ? "tag" : "folder")
                            .foregroundStyle(.secondary)
                        Text(node.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text("\(node.setCount)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selectionBackground(for: node))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, CGFloat(level) * 16 + 8)

            if isCategoryExpanded(node), !node.children.isEmpty {
                ForEach(node.children) { child in
                    AnyView(categoryTreeRow(for: child, level: level + 1))
                }
            }
        }
    }

    @ViewBuilder
    private func selectionBackground(for node: CategoryNode) -> some View {
        if selectedCategoryPath == node.path {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
        } else {
            Color.clear
        }
    }

    private func selectCategory(_ node: CategoryNode) {
        selectionID = nil
        selectedCategoryPath = node.path
        onCategorySelected(node.path)
        expandAncestors(of: node.path)
    }

    private func toggleCategoryExpansion(_ node: CategoryNode) {
        let id = node.id
        if expandedCategoryIDs.contains(id) {
            expandedCategoryIDs.remove(id)
        } else {
            expandedCategoryIDs.insert(id)
        }
    }

    private func isCategoryExpanded(_ node: CategoryNode) -> Bool {
        expandedCategoryIDs.contains(node.id) || selectedCategoryPath?.starts(with: node.path) == true
    }

    private func expandAncestors(of path: [String]) {
        guard path.count > 1 else { return }
        for depth in 1..<path.count {
            let prefix = Array(path.prefix(depth))
            expandedCategoryIDs.insert(categoryID(for: prefix))
        }
    }

    private func categoryID(for path: [String]) -> String {
        path.joined(separator: "\u{001F}")
    }

    private final class MutableCategoryNode {
        let name: String
        let path: [String]
        var setIDs: Set<PersistentIdentifier> = []
        var children: [MutableCategoryNode] = []

        init(name: String, path: [String]) {
            self.name = name
            self.path = path
        }
    }

    private struct CategoryNode: Identifiable {
        let id: String
        let name: String
        let path: [String]
        let setIDs: Set<PersistentIdentifier>
        let children: [CategoryNode]

        var setCount: Int { setIDs.count }
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
                selectedCategoryPath = nil
                onCategorySelected(nil)
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
        selectedCategoryPath = nil
        onCategorySelected(nil)
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
