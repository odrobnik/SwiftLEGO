import SwiftUI
import SwiftData

struct SetDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismissAction
    @Bindable var brickSet: BrickSet
    let partFilter: ((Part) -> Bool)?

    init(brickSet: BrickSet, partFilter: ((Part) -> Bool)? = nil) {
        self._brickSet = Bindable(brickSet)
        self.partFilter = partFilter
    }

    private var partsGroupedByColor: [(color: String, parts: [Part])] {
        let filteredParts = brickSet.parts.filter { part in
            partFilter?(part) ?? true
        }

        guard !filteredParts.isEmpty else { return [] }

        let grouped = Dictionary(grouping: filteredParts) { part in
            normalizeColorName(part.colorName)
        }

        return grouped
            .map { (color: $0.key, parts: $0.value.sorted(by: partSortComparator)) }
            .sorted { $0.color < $1.color }
    }

    var body: some View {
        List {
            if partsGroupedByColor.isEmpty {
                Section {
                    Text("No parts to display.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(partsGroupedByColor, id: \.color) { group in
                    Section(group.color) {
                        ForEach(group.parts) { part in
                            PartRowView(part: part)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(brickSet.name)
    }

    private func normalizeColorName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown Color" : trimmed
    }

    private func partSortComparator(_ lhs: Part, _ rhs: Part) -> Bool {
        if lhs.name != rhs.name {
            return lhs.name < rhs.name
        }

        return lhs.partID < rhs.partID
    }
}

private struct PartRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var part: Part

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                Text(part.name)
                    .font(.headline)

                Text("\(part.partID) • \(part.colorName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .center, spacing: 4) {
                Text("\(part.quantityHave) of \(part.quantityNeeded)")
                    .font(.title3.bold())

                Stepper("", value: $part.quantityHave, in: 0...part.quantityNeeded)
                    .labelsHidden()
            }
            .frame(minWidth: 80, idealWidth: 100)
            .onChange(of: part.quantityHave) { _ in
                try? modelContext.save()
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = part.imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: 64, height: 64)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemFill))
            .frame(width: 64, height: 64)
            .overlay {
                Image(systemName: "cube.transparent")
                    .foregroundStyle(.secondary)
            }
    }
}

#Preview("Set Detail") {
    let container = SwiftLEGOModelContainer.preview
    let context = ModelContext(container)
    let set = try! context.fetch(FetchDescriptor<BrickSet>()).first!

    return NavigationStack {
        SetDetailView(brickSet: set)
    }
    .modelContainer(container)
}
