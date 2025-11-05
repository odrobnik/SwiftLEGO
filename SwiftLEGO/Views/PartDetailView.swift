import SwiftUI
import SwiftData
import BrickCore

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
            .map { group in
                let sortedParts = group.value.sorted { lhs, rhs in
                    Part.subpartSortComparator(lhs, rhs, parentPartID: part.partID)
                }
                return (color: group.key, parts: sortedParts)
            }
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
        .quickLookPresenter()
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

}

private struct PartThumbnailImage: View {
    let part: Part

    var body: some View {
        QuickLookThumbnail(item: part, gesture: .tap) {
            if let url = part.thumbnailImageURL {
                ThumbnailImage(url: url) { phase in
                    switch phase {
                    case .empty, .loading:
                        ProgressView()
                            .frame(width: 96, height: 96)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        .frame(width: 96, height: 96)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemFill))
            .frame(width: 96, height: 96)
            .overlay {
                GeometryReader { proxy in
                    let dimension = min(proxy.size.width, proxy.size.height) * 0.6
                    Image(systemName: "cube.transparent")
                        .resizable()
                        .scaledToFit()
                        .frame(width: dimension, height: dimension)
                        .foregroundStyle(.secondary)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
    }
}
