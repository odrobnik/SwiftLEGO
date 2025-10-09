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
    @State private var showMissingOnly: Bool = false

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

    private var minifigures: [Minifigure] {
        brickSet.minifigures.sorted { lhs, rhs in
            if lhs.name != rhs.name {
                return lhs.name < rhs.name
            }
            return lhs.identifier < rhs.identifier
        }
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
            let matchesSection = part.inventorySection == selectedSection
            let matchesMissingToggle = !showMissingOnly || part.quantityHave < part.quantityNeeded
            return matchesFilter && matchesSection && matchesMissingToggle
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
            headerSection

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
                            PartRowView(part: part, isFilteringMissing: showMissingOnly)
                        }
                    }
                }
            }

            if !minifigures.isEmpty {
                minifigureSection
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search parts")
        .toolbarTitleDisplayMode(.inline)
        .navigationTitle("\(brickSet.setNumber) \(brickSet.name)")
        .toolbar {
            if partFilter != nil, let onShowEntireSet {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onShowEntireSet()
                    } label: {
                        Label("Show Entire Set", systemImage: "rectangle.stack")
                    }
                }
            }
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

    private var minifigureSection: some View {
        Section("Minifigures") {
            ForEach(minifigures) { minifigure in
                NavigationLink {
                    MinifigureDetailView(minifigure: minifigure)
                } label: {
                    MinifigureRowView(minifigure: minifigure)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var headerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 16) {
                HeaderThumbnail(brickSet: brickSet)

                VStack(alignment: .leading, spacing: 8) {
                    Text(brickSet.setNumber)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(brickSet.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)

                    let categories = brickSet.normalizedCategoryPath(uncategorizedTitle: "Uncategorized")
                    if !categories.isEmpty {
                        Text(categories.joined(separator: " / "))
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

private struct HeaderThumbnail: View {
    let brickSet: BrickSet

    var body: some View {
        thumbnail
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
                        .frame(width: 96, height: 96)
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
            .frame(width: 96, height: 96)
            .overlay {
                Image(systemName: "cube.transparent")
                    .foregroundStyle(.secondary)
            }
    }
}

private struct MinifigureRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var minifigure: Minifigure

    private var quantityBinding: Binding<Int> {
        Binding(
            get: { minifigure.quantityHave },
            set: { updateQuantity(to: $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                thumbnail

                VStack(alignment: .leading, spacing: 6) {
                    Text(minifigure.name)
                        .font(.headline)

                Text("\(minifigure.identifier)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

                VStack(alignment: .center, spacing: 4) {
                    Text("\(minifigure.quantityHave) of \(minifigure.quantityNeeded)")
                        .font(.title3.bold())
                        .contentTransition(.numericText())

                    Stepper("", value: quantityBinding, in: 0...max(0, minifigure.quantityNeeded))
                        .labelsHidden()
                }
                .frame(minWidth: 80, idealWidth: 100)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = minifigure.imageURL {
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
                Image(systemName: "person.fill")
                    .foregroundStyle(.secondary)
            }
    }

    private func updateQuantity(to newValue: Int) {
        let clamped = max(0, min(newValue, minifigure.quantityNeeded))
        let oldValue = minifigure.quantityHave
        guard clamped != oldValue else { return }

        let update = {
            minifigure.quantityHave = clamped
            try? modelContext.save()
        }

        withAnimation {
            update()
        }
    }
}

struct PartRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var part: Part
    let isFilteringMissing: Bool

    private var quantityBinding: Binding<Int> {
        Binding(
            get: { part.quantityHave },
            set: { newValue in
                updateQuantity(to: newValue)
            }
        )
    }

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
                    .contentTransition(.numericText())

                Stepper("", value: quantityBinding, in: 0...part.quantityNeeded)
                    .labelsHidden()
            }
            .frame(minWidth: 80, idealWidth: 100)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                let shouldAnimate = isFilteringMissing && part.quantityHave < part.quantityNeeded
                let update = {
                    part.quantityHave = part.quantityNeeded
                    try? modelContext.save()
                }

                if shouldAnimate {
                    withAnimation(.easeInOut) {
                        update()
                    }
                } else {
                    update()
                }
            } label: {
                Label("Have All", systemImage: "checkmark.circle.fill")
            }
            .tint(.green)
            .disabled(part.quantityHave >= part.quantityNeeded)
        }
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

    private func updateQuantity(to newValue: Int) {
        let clampedValue = max(0, min(newValue, part.quantityNeeded))
        let oldValue = part.quantityHave
        guard clampedValue != oldValue else { return }

        let shouldAnimate = isFilteringMissing && oldValue < part.quantityNeeded && clampedValue >= part.quantityNeeded
        let update = {
            part.quantityHave = clampedValue
            try? modelContext.save()
        }

        withAnimation {
            update()
        }
//
//        if shouldAnimate && isFilteringMissing {
//            withAnimation(.easeInOut) {
//                update()
//            }
//        } else {
//            update()
//        }
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
