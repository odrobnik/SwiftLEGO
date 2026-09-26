import SwiftUI
import SwiftData
import BrickCore

struct PartDetailView: View {
    let part: Part
    @State private var showMissingOnly: Bool = false

    private var partsByColor: [(color: String, parts: [Part])] {
        let subparts = showMissingOnly
            ? part.subparts.filter { $0.quantityHave < $0.quantityNeeded }
            : part.subparts

        return Dictionary(grouping: subparts) { subpart in
            normalizeColorName(subpart.colorName)
        }
        .map { color, parts in
            let sortedParts = parts.sorted { lhs, rhs in
                Part.subpartSortComparator(lhs, rhs, parentPartID: part.partID)
            }
            return (color: color, parts: sortedParts)
        }
        .sorted { lhs, rhs in lhs.color < rhs.color }
    }

    var body: some View {
        let groups = partsByColor

        List {
            PartHeaderSection(part: part)

            if groups.isEmpty {
                Section {
                    Text("No sub-parts to display.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(groups, id: \.color) { group in
                    Section(group.color) {
                        ForEach(group.parts) { subpart in
                            PartRowNavigationWrapper(part: subpart)
                        }
                    }
                }
            }
        }
        .environment(\.isFilteringMissingParts, showMissingOnly)
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

    private func normalizeColorName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown Color" : trimmed
    }
}

private struct PartHeaderSection: View {
    let part: Part

    var body: some View {
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
}

private struct PartThumbnailImage: View {
    let part: Part

    var body: some View {
        QuickLookThumbnail(item: part, gesture: .longPress) {
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
                            ThumbnailPlaceholder(systemImage: "cube.transparent", scalesSymbol: true, width: 96, height: 96)
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
                ThumbnailPlaceholder(systemImage: "cube.transparent", scalesSymbol: true, width: 96, height: 96)
            }
        }
        .frame(width: 96, height: 96)
    }
}
