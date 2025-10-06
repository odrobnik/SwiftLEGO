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

        let inputSetNumber = setNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                let payload = try await brickLinkService.fetchSetDetails(for: inputSetNumber)
                await MainActor.run {
                    let newSet = BrickSet(
                        setNumber: payload.setNumber,
                        name: customName.isEmpty ? payload.name : customName,
                        thumbnailURLString: payload.thumbnailURL?.absoluteString
                    )

                    let partModels = payload.parts.map { part in
                        Part(
                            partID: part.partID,
                            colorID: part.colorID,
                            quantityNeeded: part.quantityNeeded,
                            set: newSet
                        )
                    }

                    newSet.parts = partModels
                    newSet.collection = list
                    list.sets.append(newSet)
                    modelContext.insert(newSet)
                    try? modelContext.save()
                    completion(.success(newSet))
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "We couldn’t load that BrickLink set yet. Try again soon."
                    completion(.failure(error))
                }
            }

            await MainActor.run {
                isSaving = false
            }
        }
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
