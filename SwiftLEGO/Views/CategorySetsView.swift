import SwiftUI
import SwiftData

struct CategorySetsView: View {
    @Environment(\.modelContext) private var modelContext
    let categoryPath: [String]
    let sets: [BrickSet]
    let selectedSetID: PersistentIdentifier?
    let onNavigate: (ContentView.Destination) -> Void

    @State private var setBeingRenamed: BrickSet?

    private let adaptiveColumns = [
        GridItem(.adaptive(minimum: 220), spacing: 16)
    ]

    private var title: String {
        categoryPath.joined(separator: " / ")
    }

    private var groupedSets: [(sectionTitle: String, sets: [BrickSet])] {
        let groups = Dictionary(grouping: sets) { set in
            remainingPath(for: set).joined(separator: " / ")
        }

        return groups
            .map { key, value in
                let orderedSets = value.sorted { lhs, rhs in
                    if lhs.setNumber == rhs.setNumber {
                        return lhs.name < rhs.name
                    }
                    return lhs.setNumber < rhs.setNumber
                }
                let title = key.isEmpty ? "Other" : key
                return (sectionTitle: title, sets: orderedSets)
            }
            .sorted { lhs, rhs in
                if lhs.sectionTitle == "Other" {
                    return false
                }
                if rhs.sectionTitle == "Other" {
                    return true
                }
                return lhs.sectionTitle.localizedCaseInsensitiveCompare(rhs.sectionTitle) == .orderedAscending
            }
    }

    var body: some View {
        ScrollView {
            if groupedSets.isEmpty {
                EmptyStateView(
                    icon: "shippingbox",
                    title: "No Sets Found",
                    message: "No sets are tagged with this category."
                )
                .padding(.top, 80)
            } else {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(groupedSets, id: \.sectionTitle) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.sectionTitle)
                                .font(.title3.weight(.semibold))
                                .padding(.horizontal)

                            LazyVGrid(columns: adaptiveColumns, spacing: 16) {
                                ForEach(group.sets) { set in
                                    Button {
                                        onNavigate(.set(set.persistentModelID))
                                    } label: {
                                        SetCardView(brickSet: set)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button("Rename", systemImage: "pencil") {
                                            setBeingRenamed = set
                                        }
                                        Button(role: .destructive) {
                                            delete(set)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(title)
        .sheet(item: $setBeingRenamed) { set in
            RenameSetView(set: set)
        }
    }

    private func delete(_ set: BrickSet) {
        modelContext.delete(set)
        try? modelContext.save()
    }

    private func remainingPath(for set: BrickSet) -> [String] {
        let normalized = set.normalizedCategoryPath(uncategorizedTitle: "Uncategorized")

        guard normalized.count > categoryPath.count else { return [] }

        if normalized.starts(with: categoryPath) {
            return Array(normalized.dropFirst(categoryPath.count))
        }

        return normalized
    }
}
