import SwiftUI
import SwiftData

struct RenameSetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name: String
    var set: BrickSet

    init(set: BrickSet) {
        self.set = set
        _name = State(initialValue: set.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Set Name") {
                    TextField("Set Name", text: $name)
                        .submitLabel(.done)
                        .onSubmit(save)
                }
            }
            .navigationTitle("Rename Set")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard isValid else { return }
        set.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    let container = SwiftLEGOModelContainer.preview
    let set = try! ModelContext(container)
        .fetch(FetchDescriptor<BrickSet>())
        .first!

    return RenameSetView(set: set)
        .modelContainer(container)
}
