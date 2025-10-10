import SwiftUI
import SwiftData

struct PartDetailView: View {
    @Bindable var part: Part
    @State private var showMissingOnly: Bool = false

    init(part: Part) {
        self._part = Bindable(part)
    }

    private var partsByColor: [(color: String, parts: [Part])] {
        let grouped = Dictionary(grouping: filteredSubparts) { subpart in
            normalizeColorName(subpart.colorName)
        }

        return grouped
            .map { (color: $0.key, parts: $0.value.sorted(by: colorPartSortComparator)) }
            .sorted { lhs, rhs in lhs.color < rhs.color }
    }

    private var filteredSubparts: [Part] {
        showMissingOnly
            ? part.subparts.filter { $0.quantityHave < $0.quantityNeeded }
            : part.subparts
    }

    var body: some View {
        List {
            headerSection

            if partsByColor.isEmpty {
                Section {
                    Text("No sub-parts to display.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(partsByColor, id: \.color) { group in
                    Section(group.color) {
                        ForEach(group.parts) { subpart in
                            PartRowNavigationWrapper(
                                part: subpart,
                                isFilteringMissing: showMissingOnly
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("\(part.partID) \(part.name)")
        .toolbarTitleDisplayMode(.inline)
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
                PartThumbnailImage(part: part)

                VStack(alignment: .leading, spacing: 8) {
                    Text(part.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)

                    Text("\(part.partID) • \(part.colorName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(part.inventorySection.displayTitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("\(part.quantityHave) of \(part.quantityNeeded)")
                        .font(.headline)
                        .contentTransition(.numericText())
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
}

private struct PartThumbnailImage: View {
    @Bindable var part: Part

    var body: some View {
        thumbnail
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = part.imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: 96, height: 96)
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
