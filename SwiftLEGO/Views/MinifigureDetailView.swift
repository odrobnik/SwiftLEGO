import SwiftUI
import SwiftData

struct MinifigureDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var minifigure: Minifigure
    @State private var searchText: String = ""
    @State private var showMissingOnly: Bool = false

    init(minifigure: Minifigure) {
        self._minifigure = Bindable(minifigure)
    }

    private var partsByColor: [(color: String, parts: [Part])] {
        let grouped = Dictionary(grouping: filteredParts) { part in
            normalizeColorName(part.colorName)
        }

        return grouped
            .map { (color: $0.key, parts: $0.value.sorted(by: colorPartSortComparator)) }
            .sorted { lhs, rhs in lhs.color < rhs.color }
    }

    private var filteredParts: [Part] {
        var parts = minifigure.parts

        if showMissingOnly {
            parts = parts.filter { $0.quantityHave < $0.quantityNeeded }
        }

        if let searchQuery = normalizedSearchQuery {
            parts = parts.filter { matchesSearch($0, query: searchQuery) }
        }

        return parts
    }

    private var normalizedSearchQuery: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    var body: some View {
        List {
            headerSection

            if partsByColor.isEmpty {
                Section {
                    Text(normalizedSearchQuery == nil ? "No parts to display." : "No parts match your search.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(partsByColor, id: \.color) { group in
                    Section(group.color) {
                        ForEach(group.parts) { part in
                            PartRowView(part: part, isFilteringMissing: showMissingOnly)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search parts")
        .toolbarTitleDisplayMode(.inline)
        .navigationTitle("\(minifigure.identifier) \(minifigure.name)")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation {
                        showMissingOnly.toggle()
                    }
                } label: {
                    Image(systemName: showMissingOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(showMissingOnly ? Color.accentColor : Color.secondary)
                        .imageScale(.large)
                        .accessibilityLabel(showMissingOnly ? "Showing missing parts" : "Show only missing parts")
                }
                .buttonStyle(.plain)
                .help("Toggle missing parts filter")
            }
        }
    }

    private var headerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 16) {
                MinifigureThumbnail(minifigure: minifigure)

                VStack(alignment: .leading, spacing: 8) {
                    Text(minifigure.identifier)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(minifigure.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)

                    if let categoryDescription {
                        Text(categoryDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    private func normalizeColorName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown Color" : trimmed
    }

    private func colorPartSortComparator(_ lhs: Part, _ rhs: Part) -> Bool {
        if lhs.name != rhs.name {
            return lhs.name < rhs.name
        }

        return lhs.partID < rhs.partID
    }

    private var categoryDescription: String? {
        guard !minifigure.categories.isEmpty else { return nil }
        let path = minifigure.normalizedCategoryPath(uncategorizedTitle: "Uncategorized")
        guard !(path.count == 1 && path.first == "Uncategorized") else { return nil }
        return path.joined(separator: " / ")
    }

    private func matchesSearch(_ part: Part, query: String) -> Bool {
        if part.partID.lowercased() == query {
            return true
        }

        if wordPrefixes(in: part.colorName).contains(where: { $0.hasPrefix(query) }) {
            return true
        }

        if wordPrefixes(in: part.name).contains(where: { $0.hasPrefix(query) }) {
            return true
        }

        return false
    }

    private func wordPrefixes(in text: String) -> [String] {
        text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { $0.lowercased() }
    }

    private func updateQuantity(to newValue: Int) {
        let clamped = max(0, min(newValue, minifigure.quantityNeeded))
        guard clamped != minifigure.quantityHave else { return }

        withAnimation {
            minifigure.quantityHave = clamped
            try? modelContext.save()
        }
    }
}

private struct MinifigureThumbnail: View {
    let minifigure: Minifigure

    var body: some View {
        thumbnail
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = minifigure.imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: 96, height: 96)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 120, maxHeight: 120)
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
            .background(.white)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemFill))
            .frame(width: 120, height: 120)
            .overlay {
                Image(systemName: "person.fill")
                    .foregroundStyle(.secondary)
            }
    }
}

#Preview("Minifigure Detail") {
    let container = SwiftLEGOModelContainer.preview
    let context = ModelContext(container)
    let descriptor = FetchDescriptor<Minifigure>()
    let fetched = (try? context.fetch(descriptor)) ?? []
    let minifigure: Minifigure

    if let existing = fetched.first {
        minifigure = existing
    } else {
        let sample = Minifigure(
            identifier: "dp001",
            name: "Ariel, Mermaid",
            quantityNeeded: 1
        )

        sample.parts = [
            Part(
                partID: "15279",
                name: "Plant Grass Stem",
                colorID: "36",
                colorName: "Bright Green",
                quantityNeeded: 2,
                quantityHave: 1,
                inventorySection: .regular,
                minifigure: sample
            )
        ]

        context.insert(sample)
        try? context.save()
        minifigure = sample
    }

    return NavigationStack {
        MinifigureDetailView(minifigure: minifigure)
    }
    .modelContainer(container)
}
