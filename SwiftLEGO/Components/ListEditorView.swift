import SwiftUI
import SwiftData
import BrickCore

struct ListEditorView: View {
    let mode: EditorState
    let onSubmit: (EditorResult) -> Void
    var onDelete: ((CollectionList) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @FocusState private var isNameFocused: Bool

    private var title: String {
        switch mode {
        case .create:
            return "New List"
        case .rename:
            return "Rename List"
        }
    }

    private var primaryButtonTitle: String {
        switch mode {
        case .create:
            return "Create"
        case .rename:
            return "Save"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("List Name") {
                    TextField("Friends Hotel Lot", text: $name)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit(save)
                }

                if case let .rename(list) = mode, let onDelete {
                    Section {
                        Button(role: .destructive) {
                            onDelete(list)
                            dismiss()
                        } label: {
                            Label("Delete List", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(primaryButtonTitle) {
                        save()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                name = initialName()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    isNameFocused = true
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func initialName() -> String {
        switch mode {
        case .create:
            return ""
        case .rename(let list):
            return list.name
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        switch mode {
        case .create:
            onSubmit(.created(trimmed))
        case .rename(let list):
            onSubmit(.renamed(list, trimmed))
        }
        dismiss()
    }
}

#Preview("Create") {
    ListEditorView(
        mode: .create,
        onSubmit: { _ in }
    )
}

#Preview("Rename") {
    let container = SwiftLEGOModelContainer.preview
    let context = ModelContext(container)
    let list = CollectionList(name: "Used Collection #3")
    context.insert(list)

    return ListEditorView(
        mode: .rename(list),
        onSubmit: { _ in }
    )
    .modelContainer(container)
}
