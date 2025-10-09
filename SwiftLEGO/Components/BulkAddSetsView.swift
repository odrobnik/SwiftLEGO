import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct BulkAddSetsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var list: CollectionList
    let completion: (Result<[BrickSet], Error>) -> Void

    @State private var isImporterPresented = false
    @State private var fileName: String?
    @State private var entries: [ImportedSet] = []
    @State private var statusByID: [UUID: ImportStatus] = [:]
    @State private var parseError: String?
    @State private var isProcessing = false
    @State private var summaryMessage: String?
    @State private var didCompleteImport = false
    @State private var importTask: Task<Void, Never>?

    private let brickLinkService = BrickLinkService()
    private let allowedContentTypes: [UTType] = [.plainText, .utf8PlainText, .commaSeparatedText]

    var body: some View {
        NavigationStack {
            Form {
                Section("Text File") {
                    Button {
                        isImporterPresented = true
                    } label: {
                        Label(fileName ?? "Select Text File", systemImage: "doc.badge.plus")
                            .foregroundColor(.accentColor)
                    }
                    .disabled(isProcessing)

                    Button {
                        loadFromPasteboard()
                    } label: {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                    }
                    .disabled(isProcessing)

                    Text("Each line should be formatted like `30510, 90 Years of Cars`. The name is optional.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if let parseError {
                        Label(parseError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    } else if !entries.isEmpty {
                        Text("Ready to import \(entries.count) set\(entries.count == 1 ? "" : "s").")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if !entries.isEmpty {
                    Section("Import Queue") {
                        ForEach(entries) { entry in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.normalizedSetNumber)
                                        .font(.body.weight(.semibold))
                                    if let customName = entry.customName, !customName.isEmpty {
                                        Text(customName)
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 12)
                                statusView(for: statusByID[entry.id] ?? .pending)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if let summaryMessage, !summaryMessage.isEmpty {
                    Section {
                        Text(summaryMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(isProcessing && entries.isEmpty)
            .navigationTitle("Bulk Add Sets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isProcessing {
                        Button("Cancel", role: .cancel) {
                            cancelImport()
                        }
                    } else if !didCompleteImport {
                        Button("Close", role: .cancel) {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isProcessing {
                        ProgressView()
                    } else if didCompleteImport {
                        Button("Close") {
                            dismiss()
                        }
                    } else {
                        Button("Import", action: startImport)
                            .disabled(entries.isEmpty)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    parseError = "No file was selected."
                    return
                }
                loadFile(at: url)
            case .failure(let error):
                parseError = error.localizedDescription
            }
        }
    }
}

// MARK: - Private helpers

private extension BulkAddSetsView {
    struct ImportedSet: Identifiable {
        let id = UUID()
        let originalLine: String
        let rawSetNumber: String
        let normalizedSetNumber: String
        let customName: String?
    }

    enum ImportStatus: Equatable {
        case pending
        case inProgress
        case success
        case failure(String)
    }

    enum BulkImportError: LocalizedError {
        case noSetsImported
        case cancelled

        var errorDescription: String? {
            switch self {
            case .noSetsImported:
                return "No sets could be imported from the selected file."
            case .cancelled:
                return "The import was cancelled."
            }
        }
    }

    func loadFile(at url: URL) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer {
            if needsAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let contents = String(decoding: data, as: UTF8.self)
            fileName = url.lastPathComponent
            didCompleteImport = false
            parseContents(contents)
        } catch {
            parseError = "We couldn’t read that file. \(error.localizedDescription)"
            entries = []
            statusByID = [:]
            fileName = nil
            didCompleteImport = false
        }
    }

    func loadFromPasteboard() {
#if canImport(UIKit)
        let clipboardString = UIPasteboard.general.string
#elseif canImport(AppKit)
        let clipboardString = NSPasteboard.general.string(forType: .string)
#else
        let clipboardString: String? = nil
#endif

        guard let clipboardString, !clipboardString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            parseError = "No text entries were found on the clipboard."
            return
        }

        fileName = "Clipboard"
        didCompleteImport = false
        parseContents(clipboardString)
    }

    func parseContents(_ contents: String) {
        let lines = contents.components(separatedBy: .newlines)
        var parsed: [ImportedSet] = []

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            let split = trimmed.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            guard let numberPart = split.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !numberPart.isEmpty else {
                continue
            }

            let namePart = split.count > 1
                ? split[1].trimmingCharacters(in: .whitespacesAndNewlines)
                : nil

            let normalized = SetImportUtilities.normalizedSetNumber(numberPart)
            let customName = (namePart?.isEmpty == false) ? namePart : nil

            parsed.append(
                ImportedSet(
                    originalLine: trimmed,
                    rawSetNumber: numberPart,
                    normalizedSetNumber: normalized,
                    customName: customName
                )
            )
        }

        entries = parsed
        statusByID = Dictionary(uniqueKeysWithValues: parsed.map { ($0.id, .pending) })
        didCompleteImport = false

        if parsed.isEmpty {
            parseError = "No valid set entries were found in the selected file."
        } else {
            parseError = nil
        }

        summaryMessage = nil
    }

    func startImport() {
        guard !entries.isEmpty else {
            parseError = "Choose a text file before importing."
            return
        }

        if isProcessing {
            return
        }

        isProcessing = true
        summaryMessage = nil
        statusByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, .pending) })
        didCompleteImport = false
        importTask?.cancel()

        importTask = Task { @MainActor in
            var importedSets: [BrickSet] = []
            var wasCancelled = false

            for entry in entries {
                if Task.isCancelled {
                    wasCancelled = true
                    break
                }

                statusByID[entry.id] = .inProgress

                do {
                    try Task.checkCancellation()

                    let normalizedNumber = entry.normalizedSetNumber
                    let existingSet = try existingSetWithInventory(for: normalizedNumber)

                    try Task.checkCancellation()

                    let newSet: BrickSet

                    if let existingSet {
                        try Task.checkCancellation()
                        newSet = SetImportUtilities.persistSet(
                            list: list,
                            modelContext: modelContext,
                            setNumber: existingSet.setNumber,
                            defaultName: existingSet.name,
                            customName: entry.customName,
                            thumbnailURLString: existingSet.thumbnailURLString,
                            parts: SetImportUtilities.partPayloads(from: existingSet.parts),
                            categories: SetImportUtilities.categoryPayloads(from: existingSet.categories),
                            minifigures: SetImportUtilities.minifigurePayloads(from: existingSet.minifigures)
                        )
                    } else {
                        let payload = try await brickLinkService.fetchSetDetails(for: normalizedNumber)
                        try Task.checkCancellation()
                        newSet = SetImportUtilities.persistSet(
                            list: list,
                            modelContext: modelContext,
                            setNumber: payload.setNumber,
                            defaultName: payload.name,
                            customName: entry.customName,
                            thumbnailURLString: payload.thumbnailURL?.absoluteString,
                            parts: payload.parts,
                            categories: payload.categories,
                            minifigures: payload.minifigures
                        )
                    }

                    importedSets.append(newSet)
                    statusByID[entry.id] = .success
                } catch is CancellationError {
                    statusByID[entry.id] = .failure("Cancelled")
                    wasCancelled = true
                    break
                } catch {
                    statusByID[entry.id] = .failure(error.localizedDescription)
                }
            }

            if Task.isCancelled {
                wasCancelled = true
            }

            if wasCancelled {
                for entry in entries where statusByID[entry.id] == .inProgress {
                    statusByID[entry.id] = .failure("Cancelled")
                }
            }

            isProcessing = false
            importTask = nil

            let successCount = importedSets.count
            let failureCount = statusByID.values.reduce(into: 0) { partialResult, status in
                if case .failure = status {
                    partialResult += 1
                }
            }
            let pendingCount = entries.count - successCount - failureCount

            if wasCancelled {
                if successCount > 0 {
                    summaryMessage = "Import cancelled after importing \(successCount) set\(successCount == 1 ? "" : "s")."
                    completion(.success(importedSets))
                    didCompleteImport = true
                } else {
                    summaryMessage = "Import cancelled."
                    completion(.failure(BulkImportError.cancelled))
                    didCompleteImport = false
                }
                return
            }

            if successCount > 0 {
                if failureCount > 0 {
                    summaryMessage = "Imported \(successCount) set\(successCount == 1 ? "" : "s"). \(failureCount) failed."
                } else if pendingCount > 0 {
                    summaryMessage = "Imported \(successCount) set\(successCount == 1 ? "" : "s"). \(pendingCount) pending."
                } else {
                    summaryMessage = "Successfully imported \(successCount) set\(successCount == 1 ? "" : "s")."
                }
                completion(.success(importedSets))
                didCompleteImport = true
            } else {
                if failureCount > 0 {
                    summaryMessage = "All imports failed. Review the errors above."
                } else {
                    summaryMessage = "No sets could be imported. Review the results above and try again."
                }
                completion(.failure(BulkImportError.noSetsImported))
                didCompleteImport = false
            }

            importTask = nil
        }
    }

    @MainActor
    func existingSetWithInventory(for setNumber: String) throws -> BrickSet? {
        let descriptor = FetchDescriptor<BrickSet>(
            predicate: #Predicate { $0.setNumber == setNumber }
        )

        let sets = try modelContext.fetch(descriptor)
        return sets.first(where: { !$0.parts.isEmpty })
    }

    @ViewBuilder
    func statusView(for status: ImportStatus) -> some View {
        switch status {
        case .pending:
            Label("Pending", systemImage: "clock")
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
        case .inProgress:
            ProgressView()
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            VStack(alignment: .trailing, spacing: 2) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    func cancelImport() {
        importTask?.cancel()
    }
}

#Preview {
    let container = SwiftLEGOModelContainer.preview
    let context = ModelContext(container)
    let list = CollectionList(name: "Preview Lot")
    context.insert(list)
    return BulkAddSetsView(list: list) { _ in }
        .modelContainer(container)
}
