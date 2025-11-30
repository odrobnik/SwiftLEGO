import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import BrickCore

struct ListSidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(animation: .default) private var lists: [CollectionList]
    @Binding var selectionID: PersistentIdentifier?
    @Binding var selectedCategoryPath: [String]?
    @State private var editorState: EditorState?
    @State private var expandedCategoryIDs: Set<String> = []
    @State private var setBeingEdited: BrickSet?
    @State private var exportConfiguration = ExportConfiguration()
    @State private var isImportingInventory = false
    @State private var inventoryAlert: InventoryAlert?
    @State private var importingListIDs: Set<PersistentIdentifier> = []
    @State private var importStatusMessage: String?
    @State private var pendingImportURL: URL?
    let onSetSelected: (BrickSet) -> Void
    let onCategorySelected: ([String]?) -> Void
    private let brickLinkService = BrickLinkService()

    private var listCountDescription: String {
        "\(lists.count) list\(lists.count == 1 ? "" : "s")"
    }
    private let uncategorizedCategoryTitle = "Uncategorized"
    private let rootCategoryTitle = CategoryConstants.rootCategoryTitle

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
            ToolbarItemGroup(placement: .secondaryAction) {
                Button {
                    beginInventoryImport()
                } label: {
                    Label("Import Collection", systemImage: "square.and.arrow.down")
                }

                Menu {
                    Button {
                        beginInventoryExport()
                    } label: {
                        Label("Export Collection", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        beginWantedListExport()
                    } label: {
                        Label("Export Wanted List", systemImage: "square.and.arrow.up.on.square")
                    }
                } label: {
                    Label("Export", systemImage: "shippingbox")
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
        .sheet(item: $setBeingEdited) { set in
            SetEditView(set: set)
        }
        .onChange(of: selectedCategoryPath) { _, newValue in
            if let path = newValue {
                expandAncestors(of: path)
            }
        }
        .fileExporter(
            isPresented: $exportConfiguration.isPresented,
            document: exportConfiguration.document,
            contentType: exportConfiguration.contentType,
            defaultFilename: exportConfiguration.filename
        ) { result in
            if case .failure(let error) = result {
                inventoryAlert = .error("\(exportConfiguration.failurePrefix): \(error.localizedDescription)")
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
                message: alert.message,
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
        let document = InventorySnapshotDocument(snapshot: snapshot)
        exportConfiguration.present(
            document: ExportDocumentEnvelope(document),
            contentType: .legoInventory,
            filename: InventorySnapshotDocument.defaultFilename(),
            failurePrefix: "Export failed"
        )
    }

    private func beginWantedListExport() {
        let inventory = WantedListExporter.makeInventory(from: Array(lists))
        let document = WantedListDocument(inventory: inventory)
        exportConfiguration.present(
            document: ExportDocumentEnvelope(document),
            contentType: .brickLinkWantedList,
            filename: WantedListDocument.defaultFilename(),
            failurePrefix: "Wanted list export failed"
        )
    }

    private func beginInventoryImport() {
        isImportingInventory = true
    }

    @MainActor
    private func processImport(from sourceURL: URL) async {
        importStatusMessage = "Reading file…"
        do {
            let data = try await loadFileData(from: sourceURL)
            importStatusMessage = "Parsing inventory…"

            let snapshot = try await decodeSnapshot(from: data)
            importStatusMessage = "Importing lists…"

            let summary = try await performImport(using: snapshot)
            inventoryAlert = .success(summary)
            importStatusMessage = nil
        } catch {
            if let importError = error as? InventoryImportError {
                inventoryAlert = .error(importError.localizedDescription)
            } else {
                inventoryAlert = .error("Import failed: \(error.localizedDescription)")
            }
            importingListIDs.removeAll()
            importStatusMessage = nil
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
    private func performImport(using snapshot: InventorySnapshot) async throws -> Text {
        if snapshot.lists.isEmpty && snapshot.sets.isEmpty {
            throw InventoryImportError.emptySnapshot
        }

        importingListIDs.removeAll()

        let existingLists = Array(lists)

        if snapshot.lists.isEmpty {
            let applyResult = snapshot.apply(to: existingLists)
            try modelContext.save()
            return Text(applyResult.summaryDescription)
        }

        let setProvider = InventoryImportSetProvider(modelContext: modelContext, service: brickLinkService)
        let setRestorer = InventorySnapshotSetRestorer(modelContext: modelContext, setProvider: setProvider)
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
                do {
                    importStatusMessage = "Syncing \(setSnapshot.setNumber)…"
                    _ = try await setRestorer.importSet(setSnapshot, into: newList)
                    importedCount += 1
                    totalImportedSets += 1
                } catch {
                    missingSetNumbers.insert(setSnapshot.setNumber)
                }
                importStatusMessage = "Importing \(uniqueName)…"
            }

            if importedCount > 0 {
                createdLists.append(newList)
            } else {
                modelContext.delete(newList)
            }

            importingListIDs.remove(listID)
        }

        importingListIDs.removeAll()

        try modelContext.save()

        var lines: [String] = []
        func appendLine(_ line: String) {
            lines.append(line)
        }

        if !createdLists.isEmpty {
            let names = createdLists.map(\.name).joined(separator: ", ")
            let importedSummary: LocalizedStringResource = "Imported ^[\(createdLists.count) list](inflect: true) (\(names)) with ^[\(totalImportedSets) set](inflect: true)."
            appendLine(String(localized: importedSummary))
        } else {
            appendLine("No lists were imported.")
        }

        if !missingSetNumbers.isEmpty {
            let missing = missingSetNumbers.sorted().joined(separator: ", ")
            let missingSummary: LocalizedStringResource = "Skipped ^[\(missingSetNumbers.count) set](inflect: true) not found in your collection: \(missing)."
            appendLine(String(localized: missingSummary))
        }

        guard !lines.isEmpty else { return Text("") }
        return Text(lines.joined(separator: "\n"))
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

    private func sanitizedListName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unnamed List" : trimmed
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
            let path = [rootCategoryTitle] + categoryPath(for: set)
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
    let message: Text

    var title: String {
        switch kind {
        case .success:
            return "Import Complete"
        case .error:
            return "Inventory Error"
        }
    }

    static func success(_ message: Text) -> InventoryAlert {
        InventoryAlert(kind: .success, message: message)
    }

    static func error(_ message: String) -> InventoryAlert {
        InventoryAlert(kind: .error, message: Text(verbatim: message))
    }
}

private struct ExportConfiguration {
    var isPresented = false
    var document: ExportDocumentEnvelope = ExportDocumentEnvelope(InventorySnapshotDocument(snapshot: .empty))
    var contentType: UTType = .legoInventory
    var filename: String = InventorySnapshotDocument.defaultFilename()
    var failurePrefix: String = "Export failed"

    mutating func present(
        document: ExportDocumentEnvelope,
        contentType: UTType,
        filename: String,
        failurePrefix: String
    ) {
        self.document = document
        self.contentType = contentType
        self.filename = filename
        self.failurePrefix = failurePrefix
        isPresented = true
    }
}

private struct ExportDocumentEnvelope: FileDocument {
    static var readableContentTypes: [UTType] { [.legoInventory, .brickLinkWantedList] }
    private let writer: (WriteConfiguration) throws -> FileWrapper

    init(_ document: some FileDocument) {
        let storedDocument = document
        self.writer = { configuration in
            try storedDocument.fileWrapper(configuration: configuration)
        }
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try writer(configuration)
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
