import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ListSidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(animation: .default) private var lists: [CollectionList]
    @Binding var selectionID: PersistentIdentifier?
    @Binding var selectedCategoryPath: [String]?
    @State private var editorState: EditorState?
    @State private var expandedCategoryIDs: Set<String> = []
    @State private var setBeingRenamed: BrickSet?
    @State private var exportDocument = InventorySnapshotDocument(snapshot: .empty)
    @State private var exportFilename = InventorySnapshotDocument.defaultFilename()
    @State private var isExportingInventory = false
    @State private var isImportingInventory = false
    @State private var inventoryAlert: InventoryAlert?
    @State private var importingListIDs: Set<PersistentIdentifier> = []
    @State private var importStatusMessage: String?
    @State private var pendingImportURL: URL?
    let onSetSelected: (BrickSet) -> Void
    let onCategorySelected: ([String]?) -> Void

    private var listCountDescription: String {
        "\(lists.count) list\(lists.count == 1 ? "" : "s")"
    }
    private let uncategorizedCategoryTitle = "Uncategorized"

    var body: some View {
        List {
            if let statusMessage = importStatusMessage {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(statusMessage)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
            }

            if !lists.isEmpty {
                Section("Lists") {
                    ForEach(lists) { list in
                        Button {
                            selectList(list)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "square.stack.3d.up")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(list.name)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    if importingListIDs.contains(list.persistentModelID) {
                                        HStack(spacing: 6) {
                                            ProgressView()
                                                .scaleEffect(0.6)
                                            Text("Importing…")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    } else {
                                        Text("\(list.sets.count) set\(list.sets.count == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(listSelectionBackground(for: list))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
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
                    }
                    .onDelete { indexSet in
                        indexSet.map { lists[$0] }.forEach(delete)
                    }
                }
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
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button {
                        beginInventoryImport()
                    } label: {
                        Label("Import Lists", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        beginInventoryExport()
                    } label: {
                        Label("Export Lists", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Label("Inventory Actions", systemImage: "shippingbox")
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
        .fileExporter(
            isPresented: $isExportingInventory,
            document: exportDocument,
            contentType: .legoInventory,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                inventoryAlert = .error("Export failed: \(error.localizedDescription)")
            }
        }
        .fileImporter(
            isPresented: $isImportingInventory,
            allowedContentTypes: [.legoInventory, .json]
        ) { result in
            isImportingInventory = false
            switch result {
            case .success(let url):
                pendingImportURL = url
            case .failure(let error):
                inventoryAlert = .error("Import failed: \(error.localizedDescription)")
            }
        }
        .alert(item: $inventoryAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .task(id: pendingImportURL) {
            guard let url = pendingImportURL else { return }
            await processImport(from: url)
            await MainActor.run {
                pendingImportURL = nil
            }
        }
    }

    private func delete(_ list: CollectionList) {
        if selectionID == list.persistentModelID {
            selectionID = nil
        }
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

    private func beginInventoryExport() {
        let snapshot = InventorySnapshot.make(from: Array(lists))
        exportDocument = InventorySnapshotDocument(snapshot: snapshot)
        exportFilename = InventorySnapshotDocument.defaultFilename()
        isExportingInventory = true
    }

    private func beginInventoryImport() {
        isImportingInventory = true
    }

    private func processImport(from sourceURL: URL) async {
        importStatusMessage = "Reading file…"
        do {
            let data = try await loadFileData(from: sourceURL)

            await MainActor.run {
                importStatusMessage = "Parsing inventory…"
            }

            let snapshot = try await decodeSnapshot(from: data)

            await MainActor.run {
                importStatusMessage = "Importing lists…"
            }

            let summary = try await MainActor.run {
                try performImport(using: snapshot)
            }

            await MainActor.run {
                inventoryAlert = .success(summary)
                importStatusMessage = nil
            }
        } catch {
            await MainActor.run {
                if let importError = error as? InventoryImportError {
                    inventoryAlert = .error(importError.localizedDescription)
                } else {
                    inventoryAlert = .error("Import failed: \(error.localizedDescription)")
                }
                importingListIDs.removeAll()
                importStatusMessage = nil
            }
        }
    }

    private func loadFileData(from url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return try Data(contentsOf: url)
        }.value
    }

    private func decodeSnapshot(from data: Data) async throws -> InventorySnapshot {
        try await Task.detached(priority: .userInitiated) {
            let decoder = JSONDecoder()
            return try decoder.decode(InventorySnapshot.self, from: data)
        }.value
    }

    @MainActor
    private func performImport(using snapshot: InventorySnapshot) throws -> String {
        if snapshot.lists.isEmpty && snapshot.sets.isEmpty {
            throw InventoryImportError.emptySnapshot
        }

        importingListIDs.removeAll()

        let existingLists = Array(lists)

        if snapshot.lists.isEmpty {
            let applyResult = snapshot.apply(to: existingLists)
            try modelContext.save()
            return applyResult.summaryDescription
        }

        let allSets = try modelContext.fetch(FetchDescriptor<BrickSet>())
        var setLookup: [String: BrickSet] = [:]
        for set in allSets {
            let key = normalizedSetKey(for: set.setNumber)
            if setLookup[key] == nil {
                setLookup[key] = set
            }
        }

        var usedNames = Set(existingLists.map { $0.name })
        var createdLists: [CollectionList] = []
        var totalImportedSets = 0
        var missingSetNumbers = Set<String>()

        for listSnapshot in snapshot.lists {
            let uniqueName = uniqueListName(for: listSnapshot.name, usedNames: &usedNames)
            let newList = CollectionList(name: uniqueName)
            modelContext.insert(newList)
            let listID = newList.persistentModelID
            importingListIDs.insert(listID)
            importStatusMessage = "Importing \(uniqueName)…"

            var importedCount = 0
            for setSnapshot in listSnapshot.sets {
                let key = normalizedSetKey(for: setSnapshot.setNumber)
                guard let sourceSet = setLookup[key] else {
                    missingSetNumbers.insert(setSnapshot.setNumber)
                    continue
                }

                _ = cloneSet(from: sourceSet, into: newList, using: setSnapshot)
                importedCount += 1
            }

            if importedCount > 0 {
                let perListSnapshot = InventorySnapshot(sets: listSnapshot.sets)
                _ = perListSnapshot.apply(to: [newList])
                createdLists.append(newList)
                totalImportedSets += importedCount
            } else {
                modelContext.delete(newList)
            }

            importingListIDs.remove(listID)
        }

        importingListIDs.removeAll()

        try modelContext.save()

        var messageComponents: [String] = []
        if !createdLists.isEmpty {
            let names = createdLists.map(\.name).joined(separator: ", ")
            messageComponents.append("Imported \(createdLists.count) list\(createdLists.count == 1 ? "" : "s") (\(names)) with \(totalImportedSets) set\(totalImportedSets == 1 ? "" : "s").")
        } else {
            messageComponents.append("No lists were imported.")
        }

        if !missingSetNumbers.isEmpty {
            let missing = missingSetNumbers.sorted().joined(separator: ", ")
            messageComponents.append("Skipped \(missingSetNumbers.count) set\(missingSetNumbers.count == 1 ? "" : "s") not found in your collection: \(missing).")
        }

        return messageComponents.joined(separator: "\n")
    }

    private func uniqueListName(for rawName: String, usedNames: inout Set<String>) -> String {
        let baseName = sanitizedListName(rawName)
        var candidate = baseName
        var counter = 2

        while usedNames.contains(candidate) {
            candidate = "\(baseName) \(counter)"
            counter += 1
        }

        usedNames.insert(candidate)
        return candidate
    }

    private func cloneSet(
        from source: BrickSet,
        into list: CollectionList,
        using snapshot: InventorySnapshot.SetSnapshot
    ) -> BrickSet {
        let partPayloads = SetImportUtilities.partPayloads(from: source.parts)
        let categoryPayloads = SetImportUtilities.categoryPayloads(from: source.categories)
        let minifigurePayloads = SetImportUtilities.minifigurePayloads(from: source.minifigures)
        let resolvedName = snapshot.name
        let resolvedThumbnail = snapshot.thumbnailURLString ?? source.thumbnailURLString

        return SetImportUtilities.persistSet(
            list: list,
            modelContext: modelContext,
            setNumber: source.setNumber,
            defaultName: source.name,
            customName: resolvedName,
            thumbnailURLString: resolvedThumbnail,
            parts: partPayloads,
            categories: categoryPayloads,
            minifigures: minifigurePayloads
        )
    }

    private func sanitizedListName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unnamed List" : trimmed
    }

    private func normalizedSetKey(for setNumber: String) -> String {
        SetImportUtilities.normalizedSetNumber(setNumber).lowercased()
    }

    private enum InventoryImportError: LocalizedError {
        case emptySnapshot

        var errorDescription: String? {
            "The selected file does not contain any inventory information."
        }
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

    private var categoryNodes: [CategoryNode] {
        let allSets = lists.flatMap { $0.sets }
        guard !allSets.isEmpty else { return [] }

        var nodesByID: [String: MutableCategoryNode] = [:]
        var rootNodes: [MutableCategoryNode] = []

        for set in allSets {
            let path = categoryPath(for: set)
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

    private func categoryPath(for set: BrickSet) -> [String] {
        var path = set.normalizedCategoryPath(uncategorizedTitle: uncategorizedCategoryTitle)

        if path.isEmpty {
            path = [uncategorizedCategoryTitle]
        }

        return path
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

    private func selectList(_ list: CollectionList) {
        selectedCategoryPath = nil
        selectionID = list.persistentModelID
        onCategorySelected(nil)
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

    private func listSelectionBackground(for list: CollectionList) -> some View {
        if selectionID == list.persistentModelID {
            return AnyView(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.12)))
        }
        return AnyView(Color.clear)
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

    private func selectionHighlight(for set: BrickSet) -> some View { Color.clear }
}

private struct InventoryAlert: Identifiable {
    enum Kind {
        case success
        case error
    }

    let id = UUID()
    let kind: Kind
    let message: String

    var title: String {
        switch kind {
        case .success:
            return "Import Complete"
        case .error:
            return "Inventory Error"
        }
    }

    static func success(_ message: String) -> InventoryAlert {
        InventoryAlert(kind: .success, message: message)
    }

    static func error(_ message: String) -> InventoryAlert {
        InventoryAlert(kind: .error, message: message)
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
