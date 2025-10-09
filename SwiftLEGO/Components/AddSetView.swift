import SwiftUI
import SwiftData

struct AddSetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var list: CollectionList
    let completion: (Result<BrickSet, Error>) -> Void

    @State private var setNumber: String = ""
    @State private var customName: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let brickLinkService = BrickLinkService()

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
                    Button("Cancel", role: .cancel) { dismiss() }
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

    private var isValid: Bool {
        !setNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard isValid else { return }
        errorMessage = nil
        isSaving = true

        let inputSetNumber = SetImportUtilities.normalizedSetNumber(setNumber)

        Task { @MainActor in
            do {
                let existingSet = try existingSetWithInventory(for: inputSetNumber)

                if let existingSet {
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
                errorMessage = "We couldn’t load that BrickLink set yet. Try again soon."
                completion(.failure(error))
            }

            isSaving = false
        }
    }

    @MainActor
    private func existingSetWithInventory(for setNumber: String) throws -> BrickSet? {
        let descriptor = FetchDescriptor<BrickSet>(
            predicate: #Predicate { $0.setNumber == setNumber }
        )

        let sets = try modelContext.fetch(descriptor)
        return sets.first(where: { !$0.parts.isEmpty })
    }

    @MainActor
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

        completion(.success(newSet))
        dismiss()
    }
}

#Preview {
    let container = SwiftLEGOModelContainer.preview
    let context = ModelContext(container)
    let list = CollectionList(name: "Preview Lot")
    context.insert(list)
    return AddSetView(list: list) { _ in }
        .modelContainer(container)
}
