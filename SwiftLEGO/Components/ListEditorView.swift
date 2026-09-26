import SwiftUI
import SwiftData
import BrickCore

/// Creates a collection list, or renames or deletes one, and selects it in the sidebar.
struct ListEditorView: View {
    let mode: EditorState

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var navigation
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

                if case let .rename(list) = mode {
                    Section {
                        Button(role: .destructive) {
                            navigation.delete(list, in: modelContext)
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
            }
            .task {
                // Wait for the sheet to finish presenting before raising the keyboard.
                do {
                    try await Task.sleep(for: .milliseconds(400))
                } catch {
                    return
                }
                isNameFocused = true
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

        let list: CollectionList
        switch mode {
        case .create:
            list = CollectionList(name: trimmed)
            modelContext.insert(list)
        case .rename(let existingList):
            list = existingList
            list.name = trimmed
        }

        // Save before selecting: a new model's identifier changes when it is first saved.
        try? modelContext.save()
        navigation.select(.list(list.persistentModelID))
        dismiss()
    }
}

#Preview("Create") {
    ListEditorView(mode: .create)
        .environment(AppNavigation())
        .modelContainer(SwiftLEGOModelContainer.preview)
}

#Preview("Rename") {
    let container = SwiftLEGOModelContainer.preview
    let context = ModelContext(container)
    let list = CollectionList(name: "Used Collection #3")
    context.insert(list)

    return ListEditorView(mode: .rename(list))
        .environment(AppNavigation())
        .modelContainer(container)
}
