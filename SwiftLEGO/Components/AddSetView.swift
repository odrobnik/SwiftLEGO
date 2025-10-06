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

        let inputSetNumber = normalizedSetNumber(setNumber)

        Task {
            do {
                let existingSet = try await existingSetWithInventory(for: inputSetNumber)

                if let existingSet {
                    await MainActor.run {
                        persistSet(
                            setNumber: existingSet.setNumber,
                            defaultName: existingSet.name,
                            thumbnailURLString: existingSet.thumbnailURLString,
                            parts: existingSet.parts.map {
                                BrickLinkPartPayload(
                                    partID: $0.partID,
                                    name: $0.name,
                                    colorID: $0.colorID,
                                    colorName: $0.colorName,
                                    quantityNeeded: $0.quantityNeeded,
                                    imageURL: $0.imageURL,
                                    partURL: $0.partURL
                                )
                            }
                        )
                    }
                } else {
                    let payload = try await brickLinkService.fetchSetDetails(for: inputSetNumber)
                    await MainActor.run {
                        persistSet(
                            setNumber: payload.setNumber,
                            defaultName: payload.name,
                            thumbnailURLString: payload.thumbnailURL?.absoluteString,
                            parts: payload.parts
                        )
                    }
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

    private func existingSetWithInventory(for setNumber: String) async throws -> BrickSet? {
        try await MainActor.run {
            let descriptor = FetchDescriptor<BrickSet>(
                predicate: #Predicate { $0.setNumber == setNumber }
            )

            let sets = try modelContext.fetch(descriptor)
            return sets.first(where: { !$0.parts.isEmpty })
        }
    }

    @MainActor
    private func persistSet(
        setNumber: String,
        defaultName: String,
        thumbnailURLString: String?,
        parts: [BrickLinkPartPayload]
    ) {
        let newSet = BrickSet(
            setNumber: setNumber,
            name: customName.isEmpty ? defaultName : customName,
            thumbnailURLString: thumbnailURLString
        )

        let aggregatedParts = aggregateParts(parts)

        let partModels = aggregatedParts.map { part in
            Part(
                partID: part.partID,
                name: part.name,
                colorID: part.colorID,
                colorName: part.colorName,
                quantityNeeded: part.quantityNeeded,
                quantityHave: 0,
                imageURLString: part.imageURL?.absoluteString,
                partURLString: part.partURL?.absoluteString,
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

    private func normalizedSetNumber(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else { return trimmed }

        if trimmed.contains("-") {
            return trimmed
        }

        return "\(trimmed)-1"
    }

    private func aggregateParts(_ parts: [BrickLinkPartPayload]) -> [BrickLinkPartPayload] {
        struct PartGroupKey: Hashable {
            let partID: String
            let colorID: String
        }

        let grouped = Dictionary(grouping: parts) { PartGroupKey(partID: $0.partID, colorID: $0.colorID) }

        return grouped.map { (_, group) in
            guard let sample = group.first else { fatalError("Unexpected empty group") }
            let totalNeeded = group.reduce(0) { $0 + $1.quantityNeeded }

            return BrickLinkPartPayload(
                partID: sample.partID,
                name: sample.name,
                colorID: sample.colorID,
                colorName: sample.colorName,
                quantityNeeded: totalNeeded,
                imageURL: sample.imageURL,
                partURL: sample.partURL
            )
        }
        .sorted { lhs, rhs in
            if lhs.colorName != rhs.colorName {
                return lhs.colorName < rhs.colorName
            }

            if lhs.name != rhs.name {
                return lhs.name < rhs.name
            }

            return lhs.partID < rhs.partID
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
