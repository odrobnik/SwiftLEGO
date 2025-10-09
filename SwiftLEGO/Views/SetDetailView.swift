import SwiftUI
import SwiftData

struct SetDetailView: View {
    private static let segmentedSections: [Part.InventorySection] = [
        .regular,
        .counterpart,
        .alternate,
        .extra
    ]

    @Environment(\.modelContext) private var modelContext
    @Bindable var brickSet: BrickSet
    let partFilter: ((Part) -> Bool)?
    let onShowEntireSet: (() -> Void)?
    @State private var selectedSection: Part.InventorySection
    @State private var searchText: String = ""

    init(
        brickSet: BrickSet,
        partFilter: ((Part) -> Bool)? = nil,
        onShowEntireSet: (() -> Void)? = nil
    ) {
        self._brickSet = Bindable(brickSet)
        self.partFilter = partFilter
        self.onShowEntireSet = onShowEntireSet
        self._selectedSection = State(
            initialValue: Self.initialSection(
                for: brickSet,
                partFilter: partFilter
            )
        )
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
        let partsMatchingSection = brickSet.parts.filter { part in
            let matchesFilter = partFilter?(part) ?? true
            return matchesFilter && part.inventorySection == selectedSection
        }

        guard let searchQuery = normalizedSearchQuery else {
            return partsMatchingSection
        }

        return partsMatchingSection.filter { part in
            matchesSearch(part, query: searchQuery)
        }
    }

    private var normalizedSearchQuery: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    var body: some View {
        List {
            Section {
                Picker("Inventory Section", selection: $selectedSection) {
                    ForEach(Self.segmentedSections, id: \.self) { section in
                        Text(segmentedTitle(for: section)).tag(section)
                    }
                }
                .pickerStyle(.segmented)
            }

            if partsByColor.isEmpty {
                Section {
                    Text(normalizedSearchQuery == nil ? "No parts to display." : "No parts match your search.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(partsByColor, id: \.color) { group in
                    Section(group.color) {
                        ForEach(group.parts) { part in
                            PartRowView(part: part)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search parts")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavigationTitleContent(brickSet: brickSet)
            }
            if partFilter != nil, let onShowEntireSet {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onShowEntireSet()
                    } label: {
                        Label("Show Entire Set", systemImage: "rectangle.stack")
                    }
                }
            }
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

    private func segmentedTitle(for section: Part.InventorySection) -> String {
        switch section {
        case .regular:
            return "Regular"
        case .counterpart:
            return "Counterpart"
        case .alternate:
            return "Alternate"
        case .extra:
            return "Extras"
        }
    }

    private static func initialSection(
        for brickSet: BrickSet,
        partFilter: ((Part) -> Bool)?
    ) -> Part.InventorySection {
        let filteredParts = brickSet.parts.filter { part in
            partFilter?(part) ?? true
        }

        for section in segmentedSections {
            if filteredParts.contains(where: { $0.inventorySection == section }) {
                return section
            }
        }

        return .regular
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
}

private struct NavigationTitleContent: View {
    let brickSet: BrickSet

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 2) {
                Text(brickSet.setNumber)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Text(brickSet.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = brickSet.thumbnailURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: 44, height: 44)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemFill))
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: "cube.transparent")
                    .foregroundStyle(.secondary)
            }
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
            .onChange(of: part.quantityHave) { _, _ in
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
