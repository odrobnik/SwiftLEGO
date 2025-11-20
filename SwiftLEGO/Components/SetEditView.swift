import SwiftUI
import SwiftData
import BrickCore

struct SetEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(animation: .default) private var lists: [CollectionList]
    @State private var name: String
    @State private var excludeFromWantedList: Bool
    @State private var selectedListID: PersistentIdentifier?
    var set: BrickSet

    init(set: BrickSet) {
        self.set = set
        _name = State(initialValue: set.name)
        _excludeFromWantedList = State(initialValue: set.excludeFromWantedList)
        _selectedListID = State(initialValue: set.collection?.persistentModelID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Set Name") {
                    TextField("Set Name", text: $name)
                        .submitLabel(.done)
                        .onSubmit(save)
                }

                Section("List") {
                    if sortedLists.isEmpty {
                        Text("Create a list to assign this set.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Collection", selection: $selectedListID) {
                            Text("No list")
                                .tag(PersistentIdentifier?.none)
                            ForEach(sortedLists) { list in
                                Text(list.name)
                                    .tag(Optional(list.persistentModelID))
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }

                Section("Wanted List") {
                    Toggle("Exclude from wanted exports", isOn: $excludeFromWantedList)
                        .toggleStyle(.switch)
                        .accessibilityLabel("Exclude set from wanted lists")
                    Text("Sets marked as excluded will never appear in wanted list exports.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Set")
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
        .presentationSizing(.form)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sortedLists: [CollectionList] {
        lists.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func save() {
        guard isValid else { return }
        set.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        set.excludeFromWantedList = excludeFromWantedList
        updateCollectionAssignment()
        try? modelContext.save()
        dismiss()
    }

    private func updateCollectionAssignment() {
        if let targetID = selectedListID,
           let destinationList = lists.first(where: { $0.persistentModelID == targetID }) {
            if set.collection?.persistentModelID != destinationList.persistentModelID {
                set.collection = destinationList
            }
        } else if selectedListID == nil {
            if set.collection != nil {
                set.collection = nil
            }
        }
    }
}

#Preview {
    let container = SwiftLEGOModelContainer.preview
    let set = try! ModelContext(container)
        .fetch(FetchDescriptor<BrickSet>())
        .first!

    return SetEditView(set: set)
        .modelContainer(container)
}
