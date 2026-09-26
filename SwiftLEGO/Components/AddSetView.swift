import SwiftUI
import SwiftData
import BrickCore

struct AddSetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.brickLinkService) private var brickLinkService

    let list: CollectionList

    @State private var setNumber: String = ""
    @State private var customName: String = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("BrickLink Set ID") {
                    TextField("e.g. 75060-1", text: $setNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                Section("Custom Name (Optional)") {
                    TextField("Set nickname", text: $customName)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add BrickLink Set")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        // Also stops a save in progress, so the set isn't added after all.
                        saveTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Add")
                        }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private var isSaving: Bool {
        saveTask != nil
    }

    private var isValid: Bool {
        !setNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard isValid, !isSaving else { return }
        errorMessage = nil

        let inputSetNumber = SetImportUtilities.normalizedSetNumber(setNumber)

        saveTask = Task {
            defer { saveTask = nil }

            do {
                if let existingSet = try existingSetWithInventory(for: inputSetNumber) {
                    persistSet(
                        setNumber: existingSet.setNumber,
                        defaultName: existingSet.name,
                        thumbnailURLString: existingSet.thumbnailURLString,
                        parts: SetImportUtilities.partPayloads(from: existingSet.parts),
                        categories: SetImportUtilities.categoryPayloads(from: existingSet.categories),
                        minifigures: SetImportUtilities.minifigurePayloads(from: existingSet.minifigures)
                    )
                } else {
                    let payload = try await brickLinkService.fetchSetDetails(for: inputSetNumber)
                    try Task.checkCancellation()
                    persistSet(
                        setNumber: payload.setNumber,
                        defaultName: payload.name,
                        thumbnailURLString: payload.thumbnailURL?.absoluteString,
                        parts: payload.parts,
                        categories: payload.categories,
                        minifigures: payload.minifigures
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "We couldn’t load that BrickLink set yet. Try again soon."
            }
        }
    }

    private func existingSetWithInventory(for setNumber: String) throws -> BrickSet? {
        let descriptor = FetchDescriptor<BrickSet>(
            predicate: #Predicate { $0.setNumber == setNumber }
        )

        let sets = try modelContext.fetch(descriptor)
        return sets.first(where: { !$0.parts.isEmpty })
    }

    private func persistSet(
        setNumber: String,
        defaultName: String,
        thumbnailURLString: String?,
        parts: [BrickLinkPartPayload],
        categories: [SetCategoryPayload],
        minifigures: [BrickLinkMinifigurePayload]
    ) {
        let newSet = SetImportUtilities.persistSet(
            list: list,
            modelContext: modelContext,
            setNumber: setNumber,
            defaultName: defaultName,
            customName: customName.isEmpty ? nil : customName,
            thumbnailURLString: thumbnailURLString,
            parts: parts,
            categories: categories,
            minifigures: minifigures
        )

        applyInstanceNumbering(for: newSet, defaultName: defaultName)
        dismiss()
    }

    private func applyInstanceNumbering(for set: BrickSet, defaultName: String) {
        let trimmedCustomName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredName = trimmedCustomName.isEmpty ? defaultName : trimmedCustomName

        SetImportUtilities.applyInstanceNumbering(
            for: set.setNumber,
            in: list,
            preferredName: preferredName,
            modelContext: modelContext
        )
    }
}

#Preview {
    let container = SwiftLEGOModelContainer.preview
    let context = ModelContext(container)
    let list = CollectionList(name: "Preview Lot")
    context.insert(list)
    return AddSetView(list: list)
        .modelContainer(container)
}
