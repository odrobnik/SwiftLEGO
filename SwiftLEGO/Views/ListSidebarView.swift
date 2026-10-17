import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import BrickCore

struct ListSidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.brickLinkService) private var brickLinkService
    @Environment(AppNavigation.self) private var navigation
    @Query(animation: .default) private var lists: [CollectionList]
    @Query(animation: .default) private var orders: [BrickOrder]
    @State private var sidebarState = SidebarState()
    @State private var exportConfiguration = ExportConfiguration()
    @State private var isImportingInventory = false
    @State private var isImportingOrder = false
    @State private var importAlert: ImportAlert?
    @State private var importStatusMessage: String?
    @State private var pendingImportURL: URL?
    @State private var pendingOrderImportURL: URL?

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
                        SidebarListRow(list: list)
                    }
                    .onDelete { indexSet in
                        for list in indexSet.map({ lists[$0] }) {
                            navigation.delete(list, in: modelContext)
                        }
                    }
                }
            }

            if !orders.isEmpty {
                Section("Orders") {
                    ForEach(orders) { order in
                        SidebarOrderRow(order: order)
                    }
                    .onDelete { indexSet in
                        for order in indexSet.map({ orders[$0] }) {
                            navigation.delete(order, in: modelContext)
                        }
                    }
                }
            }

            CategoryTreeSection()
        }
        .environment(sidebarState)
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    sidebarState.editorState = .create
                } label: {
                    Label("Add List", systemImage: "plus")
                }
            }
            ToolbarItemGroup(placement: .secondaryAction) {
                Button {
                    isImportingInventory = true
                } label: {
                    Label("Import Collection", systemImage: "square.and.arrow.down")
                }

                Button {
                    isImportingOrder = true
                } label: {
                    Label("Import Order", systemImage: "cart.badge.plus")
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
            if lists.isEmpty && orders.isEmpty {
                EmptyStateView(
                    icon: "square.stack.3d.up",
                    title: "Create Your First List",
                    message: "Lists help you group LEGO sets by lot, collection, or theme."
                )
                .padding()
            }
        }
        .sheet(item: $sidebarState.editorState) { state in
            ListEditorView(mode: state)
                .environment(navigation)
        }
        .onChange(of: navigation.selectedCategoryPath) { _, path in
            if let path {
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
                importAlert = .error("\(exportConfiguration.failurePrefix): \(error.localizedDescription)")
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
                importAlert = .error("Import failed: \(error.localizedDescription)")
            }
        }
        .fileImporter(
            isPresented: $isImportingOrder,
            allowedContentTypes: [.html]
        ) { result in
            isImportingOrder = false
            switch result {
            case .success(let url):
                pendingOrderImportURL = url
            case .failure(let error):
                importAlert = .error("Order import failed: \(error.localizedDescription)")
            }
        }
        .alert(item: $importAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: alert.message,
                dismissButton: .default(Text("OK"))
            )
        }
        .task(id: pendingImportURL) {
            guard let url = pendingImportURL else { return }
            await processImport(from: url)
            // Picking another file cancels this import and starts a new task for it;
            // only clear the request if it is still this one.
            if pendingImportURL == url {
                pendingImportURL = nil
            }
        }
        .task(id: pendingOrderImportURL) {
            guard let url = pendingOrderImportURL else { return }
            await processOrderImport(from: url)
            if pendingOrderImportURL == url {
                pendingOrderImportURL = nil
            }
        }
    }

    private func beginInventoryExport() {
        let snapshot = InventorySnapshot.make(from: Array(lists), orders: Array(orders))
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

    private func processImport(from sourceURL: URL) async {
        importStatusMessage = "Reading file…"
        do {
            let data = try await loadFileData(from: sourceURL)
            importStatusMessage = "Parsing inventory…"

            let snapshot = try await decodeSnapshot(from: data)
            importStatusMessage = "Importing lists…"

            let summary = try await performImport(using: snapshot)
            importAlert = .success(summary)
        } catch is CancellationError {
            // The import stopped early; what it imported so far is kept.
        } catch let importError as InventoryImportError {
            importAlert = .error(importError.localizedDescription)
        } catch {
            importAlert = .error("Import failed: \(error.localizedDescription)")
        }

        sidebarState.importingListIDs.removeAll()
        importStatusMessage = nil
    }

    private func processOrderImport(from sourceURL: URL) async {
        importStatusMessage = "Reading order…"
        do {
            let data = try await loadFileData(from: sourceURL)
            importStatusMessage = "Parsing order…"

            let parsed = try await BrickLinkOrderDetailParser().parseOrderDetail(
                htmlData: data,
                baseURL: URL(string: "https://www.bricklink.com")
            )

            try await ensureBrickColors(for: parsed)
            importStatusMessage = "Importing order…"
            let orderName = inferredOrderName(from: parsed, sourceURL: sourceURL)
            let parts = makeOrderParts(from: parsed)
            guard !parts.isEmpty else {
                throw OrderImportError.noParts
            }

            let order = BrickOrder(
                name: orderName,
                orderNumber: parsed.orderID,
                sourceFilename: sourceURL.lastPathComponent
            )
            modelContext.insert(order)
            order.parts = parts
            for part in parts {
                part.order = order
            }
            try modelContext.save()

            let summary: LocalizedStringResource = "Imported \(orderName) with ^[\(parts.count) part](inflect: true)."
            importAlert = .success(Text(summary))
        } catch let importError as OrderImportError {
            importAlert = .error(importError.localizedDescription)
        } catch {
            importAlert = .error("Order import failed: \(error.localizedDescription)")
        }

        importStatusMessage = nil
    }

    private func inferredOrderName(from parsed: BrickLinkOrderDetail, sourceURL: URL) -> String {
        if let orderID = parsed.orderID, !orderID.isEmpty {
            return "Order #\(orderID)"
        }
        let filename = sourceURL.deletingPathExtension().lastPathComponent
        return filename.isEmpty ? "Order" : filename
    }

    private func makeOrderParts(from parsed: BrickLinkOrderDetail) -> [OrderPart] {
        let colorLookup = brickColorLookup()
        var aggregated: [OrderPartKey: OrderPart] = [:]

        for entry in parsed.parts {
            let trimmedName = entry.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let resolvedName = trimmedName.isEmpty ? defaultName(for: entry) : trimmedName
            let colorName = resolvedColorName(for: entry, lookup: colorLookup)
            let key = OrderPartKey(
                itemType: entry.itemType,
                partID: entry.partID,
                colorID: entry.colorID
            )

            if let existing = aggregated[key] {
                existing.quantity += entry.quantity
                if shouldReplaceOrderPartName(
                    current: existing.name,
                    candidate: resolvedName,
                    itemType: entry.itemType
                ) {
                    existing.name = resolvedName
                }
            } else {
                aggregated[key] = OrderPart(
                    itemType: OrderPart.ItemType(rawValue: entry.itemType.rawValue) ?? .part,
                    partID: entry.partID,
                    name: resolvedName,
                    colorID: entry.colorID,
                    colorName: colorName,
                    quantity: entry.quantity,
                    imageURLString: entry.imageURL?.absoluteString
                )
            }
        }

        return aggregated.values.sorted { lhs, rhs in
            let typeComparison = lhs.itemTypeRawValue.localizedCaseInsensitiveCompare(rhs.itemTypeRawValue)
            if typeComparison != .orderedSame {
                return typeComparison == .orderedAscending
            }
            if lhs.colorName != rhs.colorName {
                return lhs.colorName.localizedCaseInsensitiveCompare(rhs.colorName) == .orderedAscending
            }
            let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }
            return lhs.partID.localizedCaseInsensitiveCompare(rhs.partID) == .orderedAscending
        }
    }

    private func shouldReplaceOrderPartName(
        current: String,
        candidate: String,
        itemType: BrickLinkOrderPart.ItemType
    ) -> Bool {
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCandidate.isEmpty else { return false }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let defaultPrefix = itemType == .minifigure ? "Minifigure " : "Part "
            return current.hasPrefix(defaultPrefix) && current != trimmedCandidate
        }
        return true
    }

    private func defaultName(for entry: BrickLinkOrderPart) -> String {
        switch entry.itemType {
        case .part:
            return "Part \(entry.partID)"
        case .minifigure:
            return "Minifigure \(entry.partID)"
        }
    }

    private func resolvedColorName(
        for entry: BrickLinkOrderPart,
        lookup: [String: String]
    ) -> String {
        switch entry.itemType {
        case .minifigure:
            return "Minifigure"
        case .part:
            return lookup[entry.colorID] ?? ""
        }
    }

    private struct OrderPartKey: Hashable {
        let itemType: BrickLinkOrderPart.ItemType
        let partID: String
        let colorID: String
    }

    private func brickColorLookup() -> [String: String] {
        let descriptor = FetchDescriptor<BrickColor>()
        guard let colors = try? modelContext.fetch(descriptor), !colors.isEmpty else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: colors.map { (String($0.brickLinkColorID), $0.brickLinkName) })
    }

    private func ensureBrickColors(for parsed: BrickLinkOrderDetail) async throws {
        let neededColorIDs = Set(
            parsed.parts
                .filter { $0.itemType == .part }
                .compactMap { Int($0.colorID) }
                .filter { $0 > 0 }
        )

        guard !neededColorIDs.isEmpty else { return }

        var missing = missingColorIDs(from: neededColorIDs)
        guard !missing.isEmpty else { return }

        importStatusMessage = "Refreshing colors…"
        let localeIdentifier = localeIdentifier(for: .current)
        try await ColorImportUtilities.refreshBrickLinkColors(
            modelContext: modelContext,
            locale: localeIdentifier
        )

        missing = missingColorIDs(from: neededColorIDs)
        guard missing.isEmpty else {
            throw OrderImportError.missingColors(missing.sorted())
        }
    }

    private func missingColorIDs(from neededIDs: Set<Int>) -> Set<Int> {
        let descriptor = FetchDescriptor<BrickColor>()
        let existingIDs = (try? modelContext.fetch(descriptor))?.map(\.brickLinkColorID) ?? []
        return neededIDs.subtracting(existingIDs)
    }

    private func localeIdentifier(for locale: Locale) -> String {
        let normalized = locale.identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        let components = normalized.split(separator: "-")
        guard let language = components.first else {
            return "en-us"
        }

        let region = components.dropFirst().first ?? Substring("us")
        return "\(language)-\(region)"
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

    /// Imports the lists, sets and orders of `snapshot`. When the import task is
    /// cancelled it stops after the current set, keeps the lists imported so far and
    /// throws `CancellationError`.
    private func performImport(using snapshot: InventorySnapshot) async throws -> Text {
        if snapshot.lists.isEmpty && snapshot.sets.isEmpty && snapshot.orders.isEmpty {
            throw InventoryImportError.emptySnapshot
        }

        sidebarState.importingListIDs.removeAll()

        let existingLists = Array(lists)
        var lines: [String] = []

        if snapshot.lists.isEmpty {
            if !snapshot.sets.isEmpty {
                let applyResult = snapshot.apply(to: existingLists)
                try modelContext.save()
                lines.append(applyResult.summaryDescription)
            }
        } else {
            let setProvider = InventoryImportSetProvider(modelContext: modelContext, service: brickLinkService)
            let setRestorer = InventorySnapshotSetRestorer(modelContext: modelContext, setProvider: setProvider)
            var usedNames = Set(existingLists.map(\.name))
            var createdLists: [CollectionList] = []
            var totalImportedSets = 0
            var missingSetNumbers = Set<String>()

            for listSnapshot in snapshot.lists {
                if Task.isCancelled { break }

                let uniqueName = uniqueListName(for: listSnapshot.name, usedNames: &usedNames)
                let newList = CollectionList(name: uniqueName)
                modelContext.insert(newList)
                let listID = newList.persistentModelID
                sidebarState.importingListIDs.insert(listID)
                importStatusMessage = "Importing \(uniqueName)…"

                var importedCount = 0
                for setSnapshot in listSnapshot.sets {
                    if Task.isCancelled { break }

                    do {
                        importStatusMessage = "Syncing \(setSnapshot.setNumber)…"
                        _ = try await setRestorer.importSet(setSnapshot, into: newList)
                        importedCount += 1
                        totalImportedSets += 1
                    } catch {
                        // A fetch that failed because the import was cancelled says
                        // nothing about whether the set exists.
                        if Task.isCancelled { break }
                        missingSetNumbers.insert(setSnapshot.setNumber)
                    }
                    importStatusMessage = "Importing \(uniqueName)…"
                }

                if importedCount > 0 {
                    createdLists.append(newList)
                } else {
                    modelContext.delete(newList)
                }

                sidebarState.importingListIDs.remove(listID)
            }

            sidebarState.importingListIDs.removeAll()

            try modelContext.save()
            try Task.checkCancellation()

            if !createdLists.isEmpty {
                let names = createdLists.map(\.name).joined(separator: ", ")
                let importedSummary: LocalizedStringResource = "Imported ^[\(createdLists.count) list](inflect: true) (\(names)) with ^[\(totalImportedSets) set](inflect: true)."
                lines.append(String(localized: importedSummary))
            } else {
                lines.append("No lists were imported.")
            }

            if !missingSetNumbers.isEmpty {
                let missing = missingSetNumbers.sorted().joined(separator: ", ")
                let missingSummary: LocalizedStringResource = "Skipped ^[\(missingSetNumbers.count) set](inflect: true) not found in your collection: \(missing)."
                lines.append(String(localized: missingSummary))
            }
        }

        if let orderSummary = try importOrders(from: snapshot) {
            lines.append(orderSummary)
        }

        guard !lines.isEmpty else { return Text("") }
        return Text(lines.joined(separator: "\n"))
    }

    private func importOrders(from snapshot: InventorySnapshot) throws -> String? {
        guard !snapshot.orders.isEmpty else { return nil }
        importStatusMessage = "Importing orders…"

        var usedOrderIDs = Set(orders.map(\.id))
        var importedOrders = 0
        var totalParts = 0

        for orderSnapshot in snapshot.orders {
            let resolvedID: UUID
            if let snapshotID = orderSnapshot.id, !usedOrderIDs.contains(snapshotID) {
                resolvedID = snapshotID
            } else {
                resolvedID = UUID()
            }

            let order = BrickOrder(
                id: resolvedID,
                name: orderSnapshot.name,
                orderNumber: orderSnapshot.orderNumber,
                sourceFilename: orderSnapshot.sourceFilename,
                importedAt: orderSnapshot.importedAt ?? Date()
            )
            modelContext.insert(order)

            let parts = orderSnapshot.parts.map { part in
                OrderPart(
                    itemType: OrderPart.ItemType(rawValue: part.itemTypeRawValue) ?? .part,
                    partID: part.partID,
                    name: part.name,
                    colorID: part.colorID,
                    colorName: part.colorName,
                    quantity: part.quantity,
                    imageURLString: part.imageURLString,
                    order: order
                )
            }
            order.parts = parts

            importedOrders += 1
            totalParts += parts.count
            usedOrderIDs.insert(order.id)
        }

        try modelContext.save()

        let summary: LocalizedStringResource = "Imported ^[\(importedOrders) order](inflect: true) with ^[\(totalParts) part](inflect: true)."
        return String(localized: summary)
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

    private enum OrderImportError: LocalizedError {
        case noParts
        case missingColors([Int])

        var errorDescription: String? {
            switch self {
            case .noParts:
                return "The selected file does not contain any order parts."
            case .missingColors(let ids):
                let list = ids.map(String.init).joined(separator: ", ")
                return "Color lookup is incomplete. Missing BrickLink color IDs: \(list)."
            }
        }
    }

    private func expandAncestors(of path: [String]) {
        guard path.count > 1 else { return }
        for depth in 1..<path.count {
            sidebarState.expandedCategoryIDs.insert(CategoryNode.id(for: Array(path.prefix(depth))))
        }
    }
}

/// Sidebar state that the extracted rows read themselves, so that the row closures
/// of the sidebar's lists depend on nothing but their item.
@MainActor
@Observable
private final class SidebarState {
    var importingListIDs: Set<PersistentIdentifier> = []
    var expandedCategoryIDs: Set<String> = []
    var editorState: EditorState?
}

private struct SidebarListRow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var navigation
    @Environment(SidebarState.self) private var sidebarState
    let list: CollectionList

    var body: some View {
        Button {
            navigation.select(.list(list.persistentModelID))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    if sidebarState.importingListIDs.contains(list.persistentModelID) {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Importing…")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("^[\(list.sets.count) set](inflect: true)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .sidebarRowStyle(isSelected: navigation.selection == .list(list.persistentModelID))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                sidebarState.editorState = .rename(list)
            }
            Button(role: .destructive) {
                navigation.delete(list, in: modelContext)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private struct SidebarOrderRow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var navigation
    let order: BrickOrder

    var body: some View {
        Button {
            navigation.select(.order(order.persistentModelID))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "cart")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(order.displayName)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text("^[\(order.parts.count) item](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .sidebarRowStyle(isSelected: navigation.selection == .order(order.persistentModelID))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                navigation.delete(order, in: modelContext)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// The category tree of the sidebar. It builds the tree from its own query, so import
/// progress and selection changes in the rest of the sidebar don't rebuild it.
private struct CategoryTreeSection: View {
    @Query(animation: .default) private var lists: [CollectionList]

    var body: some View {
        if let root = CategoryNode.tree(of: lists) {
            Section {
                CategoryRootRow(name: root.name, path: root.path, setCount: root.setCount)
                ForEach(root.children) { node in
                    CategoryTreeRow(node: node)
                }
            }
        }
    }
}

private struct CategoryRootRow: View {
    @Environment(AppNavigation.self) private var navigation
    let name: String
    let path: [String]
    let setCount: Int

    var body: some View {
        Button {
            navigation.select(.category(path))
        } label: {
            HStack(spacing: 6) {
                Text(name)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(setCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .sidebarRowStyle(isSelected: navigation.selectedCategoryPath == path)
        }
        .buttonStyle(.plain)
    }
}

/// A category below the root, followed by its subcategories while it is expanded.
private struct CategoryTreeRow: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(SidebarState.self) private var sidebarState
    let node: CategoryNode

    /// The children of the root are at level 0.
    private var level: Int {
        max(node.path.count - 2, 0)
    }

    private var isExpanded: Bool {
        sidebarState.expandedCategoryIDs.contains(node.id)
            || navigation.selectedCategoryPath?.starts(with: node.path) == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                if node.children.isEmpty {
                    Color.clear
                        .frame(width: 24, height: 24)
                } else {
                    Button {
                        toggleExpansion()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    navigation.select(.category(node.path))
                } label: {
                    HStack(spacing: 8) {
                        Text(node.name)
                            .font(node.children.isEmpty ? .subheadline : .subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                        Text("\(node.setCount)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .sidebarRowStyle(isSelected: navigation.selectedCategoryPath == node.path)
                }
                .buttonStyle(.plain)
            }

            if isExpanded, !node.children.isEmpty {
                ForEach(node.children) { child in
                    CategoryTreeRow(node: child)
                }
            }
        }
        .padding(.leading, CGFloat(level) * 12)
    }

    private func toggleExpansion() {
        if sidebarState.expandedCategoryIDs.contains(node.id) {
            sidebarState.expandedCategoryIDs.remove(node.id)
        } else {
            sidebarState.expandedCategoryIDs.insert(node.id)
        }
    }
}

private extension View {
    /// The padding and selection highlight of a sidebar row.
    func sidebarRowStyle(isSelected: Bool) -> some View {
        padding(.vertical, 6)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// A category in the sidebar tree, with the number of sets filed under it.
private struct CategoryNode: Identifiable {
    let id: String
    let name: String
    let path: [String]
    let setCount: Int
    let children: [CategoryNode]

    static func id(for path: [String]) -> String {
        path.joined(separator: "\u{001F}")
    }

    /// The categories of all sets in `lists` under a root "Sets" node, or `nil` when
    /// there are no sets.
    static func tree(of lists: [CollectionList]) -> CategoryNode? {
        let allSets = lists.flatMap(\.sets)
        guard !allSets.isEmpty else { return nil }

        let rootPath = [CategoryConstants.rootCategoryTitle]
        let root = Builder(name: CategoryConstants.rootCategoryTitle, path: rootPath)
        var buildersByID = [id(for: rootPath): root]

        for set in allSets {
            let setID = set.persistentModelID
            root.setIDs.insert(setID)

            var parent = root
            var path = rootPath
            for component in categoryPath(of: set) {
                path.append(component)
                let nodeID = id(for: path)

                let node: Builder
                if let existing = buildersByID[nodeID] {
                    node = existing
                } else {
                    node = Builder(name: component, path: path)
                    buildersByID[nodeID] = node
                    parent.children.append(node)
                }

                node.setIDs.insert(setID)
                parent = node
            }
        }

        return root.build()
    }

    private static func categoryPath(of set: BrickSet) -> [String] {
        let path = set.normalizedCategoryPath(uncategorizedTitle: CategoryConstants.uncategorizedTitle)
        return path.isEmpty ? [CategoryConstants.uncategorizedTitle] : path
    }

    private final class Builder {
        let name: String
        let path: [String]
        var setIDs: Set<PersistentIdentifier> = []
        var children: [Builder] = []

        init(name: String, path: [String]) {
            self.name = name
            self.path = path
        }

        func build() -> CategoryNode {
            CategoryNode(
                id: CategoryNode.id(for: path),
                name: name,
                path: path,
                setCount: setIDs.count,
                children: children
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    .map { $0.build() }
            )
        }
    }
}

private struct ImportAlert: Identifiable {
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
            return "Import Error"
        }
    }

    static func success(_ message: Text) -> ImportAlert {
        ImportAlert(kind: .success, message: message)
    }

    static func error(_ message: String) -> ImportAlert {
        ImportAlert(kind: .error, message: Text(verbatim: message))
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
