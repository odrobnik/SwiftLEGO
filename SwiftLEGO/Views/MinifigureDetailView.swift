import SwiftUI
import SwiftData
#if canImport(BrickCore)
import BrickCore
#endif

struct MinifigureDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var minifigure: Minifigure
    @State private var showMissingOnly: Bool = false

    init(minifigure: Minifigure) {
        self._minifigure = Bindable(minifigure)
    }

    private var partsByColor: [(color: String, parts: [Part])] {
        let grouped = Dictionary(grouping: filteredParts) { part in
            normalizeColorName(part.colorName)
        }

        return grouped
            .map { group in
                let sortedParts = group.value.sorted { lhs, rhs in
                    Part.subpartSortComparator(lhs, rhs)
                }
                return (color: group.key, parts: sortedParts)
            }
            .sorted { lhs, rhs in lhs.color < rhs.color }
    }

    private var filteredParts: [Part] {
        showMissingOnly
            ? minifigure.parts.filter { $0.quantityHave < $0.quantityNeeded }
            : minifigure.parts
    }

    var body: some View {
        List {
            headerSection

            if partsByColor.isEmpty {
                Section {
                    Text("No parts to display.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(partsByColor, id: \.color) { group in
                    Section(group.color) {
                        ForEach(group.parts) { part in
                            PartRowNavigationWrapper(
                                part: part,
                                isFilteringMissing: showMissingOnly
                            )
                        }
                    }
                }
            }
        }
        .quickLookPresenter()
        .listStyle(.insetGrouped)
        .toolbarTitleDisplayMode(.inline)
        .navigationTitle("\(minifigure.displayIdentifier()) \(minifigure.displayName(includeInstanceSuffix: false))")
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
                    Text(minifigure.displayIdentifier())
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(minifigure.displayName())
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)

                    if let categoryDescription {
                        Text(categoryDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    if let owningSet = minifigure.set {
                        Text("\(owningSet.setNumber) \(owningSet.name)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func normalizeColorName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown Color" : trimmed
    }

    private var categoryDescription: String? {
        guard !minifigure.categories.isEmpty else { return nil }
        let path = minifigure.normalizedCategoryPath(uncategorizedTitle: "Uncategorized")
        guard !(path.count == 1 && path.first == "Uncategorized") else { return nil }
        return path.joined(separator: " / ")
    }

    private func updateQuantity(to newValue: Int) {
        let clamped = max(0, min(newValue, minifigure.quantityNeeded))
        guard clamped != minifigure.quantityHave else { return }

        withAnimation {
            minifigure.quantityHave = clamped
            _minifigure.wrappedValue.synchronizeParts(to: clamped)
            try? modelContext.save()
        }
    }
}

private struct MinifigureThumbnail: View {
    let minifigure: Minifigure

    var body: some View {
        QuickLookThumbnail(item: minifigure) {
            if let url = minifigure.imageURL {
                ThumbnailImage(url: url) { phase in
                    switch phase {
                    case .empty, .loading:
                        ProgressView()
                            .frame(width: 96, height: 96)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 120, maxHeight: 120)
                    case .failure(let state):
                        ZStack {
                            placeholder
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.red)
                                Button("Retry") {
                                    state.retry()
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(12)
                        }
                    }
                }
                .background(.white)
            } else {
                placeholder
            }
        }
        .frame(width: 120, height: 120)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemFill))
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
