import SwiftUI
import SwiftData

struct PartSearchResultRow: View {
    @Environment(\.modelContext) private var modelContext
    let set: BrickSet
    @Bindable var displayPart: Part
    let matchingParts: [Part]
    let contextDescription: String?
    let onShowSet: (() -> Void)?

    private var directMatch: Part? {
        matchingParts.first { $0.persistentModelID == displayPart.persistentModelID }
    }

    private var subpartMatches: [Part] {
        matchingParts.filter { $0.persistentModelID != displayPart.persistentModelID }
    }

    private var directMatchBinding: Binding<Int>? {
        guard let target = directMatch, subpartMatches.isEmpty else { return nil }
        return Binding(
            get: { target.quantityHave },
            set: { updateQuantity(for: target, to: $0) }
        )
    }

    private var thumbnailSource: Part {
        if displayPart.imageURL != nil {
            return displayPart
        }

        if let directMatch, directMatch.imageURL != nil {
            return directMatch
        }

        return subpartMatches.first ?? displayPart
    }

    private var totalMissing: Int {
        matchingParts.reduce(0) { $0 + missingCount(for: $1) }
    }

    private var totalNeeded: Int {
        matchingParts.reduce(0) { $0 + $1.quantityNeeded }
    }

    private var totalHave: Int {
        matchingParts.reduce(0) { $0 + $1.quantityHave }
    }

    @ViewBuilder
    private var summaryText: some View {
        if let directMatch, subpartMatches.isEmpty {
            Text("Missing ^[\(missingCount(for: directMatch)) part](inflect: true) • Need \(directMatch.quantityNeeded), have \(directMatch.quantityHave)")
        } else {
            Text("Missing ^[\(totalMissing) part](inflect: true) across ^[\(matchingParts.count) item](inflect: true) • Need \(totalNeeded), have \(totalHave)")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                PartThumbnail(url: thumbnailSource.imageURL)

                VStack(alignment: .leading, spacing: 6) {
                    Text(displayPart.name)
                        .font(.headline)

                    let secondaryColorName = displayPart.colorName.isEmpty ? (subpartMatches.first?.colorName ?? displayPart.colorName) : displayPart.colorName
                    Text("\(displayPart.partID) • \(secondaryColorName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let binding = directMatchBinding, let directMatch {
                    VStack(alignment: .center, spacing: 6) {
                        Text("\(directMatch.quantityHave) of \(directMatch.quantityNeeded)")
                            .font(.title3.bold())
                            .contentTransition(.numericText())
                            .multilineTextAlignment(.center)

                        Stepper("", value: binding, in: 0...directMatch.quantityNeeded)
                            .labelsHidden()
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Missing \(totalMissing)")
                            .font(.title3.bold())
                            .foregroundStyle(.orange)

                        Text("Need \(totalNeeded), have \(totalHave)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 150, alignment: .center)
                }
            }

                if let contextDescription, !contextDescription.isEmpty {
                    Text(contextDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !subpartMatches.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(subpartMatches, id: \.persistentModelID) { subpart in
                            Text(subpartSummary(for: subpart))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(alignment: .center, spacing: 12) {
                    summaryText
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if let onShowSet {
                        Button(action: onShowSet) {
                            HStack(spacing: 6) {
                                Text("\(set.setNumber) • \(set.name)")
                                    .font(.body)
                                Image(systemName: "arrow.up.right.square")
                                    .imageScale(.medium)
                            }
                            .padding(.vertical, 2)
                            .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Text("\(set.setNumber) • \(set.name)")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if let directMatch, subpartMatches.isEmpty {
                Button {
                    markComplete(for: directMatch)
                } label: {
                    Label("Have All", systemImage: "checkmark.circle.fill")
                }
                .tint(.green)
                .disabled(directMatch.quantityHave >= directMatch.quantityNeeded)
            }
        }
    }

    private func missingCount(for part: Part) -> Int {
        max(part.quantityNeeded - part.quantityHave, 0)
    }

    private func subpartSummary(for part: Part) -> LocalizedStringKey {
        let missing = missingCount(for: part)
        let colorDescription = part.colorName.isEmpty ? "Unknown color" : part.colorName
        return "• \(part.partID) • \(colorDescription) — Missing ^[\(missing) part](inflect: true) (Need \(part.quantityNeeded), have \(part.quantityHave))"
    }

    private func updateQuantity(for part: Part, to newValue: Int) {
        let clamped = max(0, min(newValue, part.quantityNeeded))
        guard clamped != part.quantityHave else { return }

        let applyChange = {
            part.quantityHave = clamped
            try? modelContext.save()
        }

        if clamped >= part.quantityNeeded {
            withAnimation(.easeInOut) {
                applyChange()
            }
        } else {
            withAnimation {
                applyChange()
            }
        }
    }

    private func markComplete(for part: Part) {
        updateQuantity(for: part, to: part.quantityNeeded)
    }
}

private struct PartThumbnail: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                ThumbnailImage(url: url) { phase in
                    switch phase {
                    case .empty, .loading:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure(let state):
                        if shouldShowRetry(for: state.error) {
                            ZStack {
                                placeholder
                                VStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.red)
                                    Button("Retry") {
                                        state.retry()
                                    }
                                    .font(.caption)
                                }
                                .padding(8)
                            }
                        } else {
                            placeholder
                        }
                    }
                }
                .background(.white)
            } else {
                placeholder
            }
        }
        .frame(width: 80, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemFill))
            .frame(width: 80, height: 60)
            .overlay {
                Image(systemName: "cube.transparent")
                    .foregroundStyle(.secondary)
            }
    }

    private func shouldShowRetry(for error: Error) -> Bool {
        if let cacheError = error as? ThumbnailCacheError,
           let code = cacheErrorStatusCode(cacheError),
           code == 404 || code == 410 {
            return false
        }

        if let urlError = error as? URLError,
           urlError.code == .fileDoesNotExist {
            return false
        }

        return true
    }

    private func cacheErrorStatusCode(_ error: ThumbnailCacheError) -> Int? {
        if case .invalidResponse(let statusCode) = error {
            return statusCode
        }
        if case .emptyData = error {
            return 404
        }
        return nil
    }
}

#Preview("Part Result Row – Direct Match") {
    let container = SwiftLEGOModelContainer.preview
    let context = ModelContext(container)
    let set = try! context.fetch(FetchDescriptor<BrickSet>()).first!
    let part: Part
    if let existing = set.parts.first {
        part = existing
    } else {
        let newPart = Part(
            partID: "3001",
            name: "Preview Brick",
            colorID: "5",
            colorName: "Red",
            quantityNeeded: 4,
            quantityHave: 1,
            set: set
        )
        context.insert(newPart)
        set.parts.append(newPart)
        part = newPart
    }

    let matches = [part]

    return PartSearchResultRow(
        set: set,
        displayPart: part,
        matchingParts: matches,
        contextDescription: "Counterpart: Preview Sample",
        onShowSet: nil
    )
    .padding()
    .modelContainer(container)
}

#Preview("Part Result Rows – Variants") {
    let container = SwiftLEGOModelContainer.preview
    let context = ModelContext(container)

    let directSet = BrickSet(setNumber: "10755-1", name: "Zane's Ninja Boat Pursuit")
    context.insert(directSet)
    let directPart = Part(
        partID: "3003",
        name: "Brick 2 x 2",
        colorID: "11",
        colorName: "Black",
        quantityNeeded: 4,
        quantityHave: 0,
        set: directSet
    )
    context.insert(directPart)

    let counterpartSet = BrickSet(setNumber: "41107-1", name: "Pop Star Limousine")
    context.insert(counterpartSet)
    let counterpartPart = Part(
        partID: "spa0001",
        name: "Accessory Pack",
        colorID: "0",
        colorName: "Black",
        quantityNeeded: 1,
        quantityHave: 0,
        inventorySection: .counterpart,
        set: counterpartSet
    )
    context.insert(counterpartPart)

    if counterpartPart.subparts.isEmpty {
        let child = Part(
            partID: "3003",
            name: "Brick 2 x 2",
            colorID: "11",
            colorName: "Black",
            quantityNeeded: 1,
            quantityHave: 0,
            parentPart: counterpartPart
        )
        context.insert(child)
        counterpartPart.subparts.append(child)
    }

    let directMatches = [directPart]
    let aggregatedMatches = [counterpartPart] + counterpartPart.subparts

    return NavigationStack {
        List {
            Section("Black") {
                PartSearchResultRow(
                    set: directSet,
                    displayPart: directPart,
                    matchingParts: directMatches,
                    contextDescription: nil,
                    onShowSet: nil
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowSeparator(.hidden)

                PartSearchResultRow(
                    set: counterpartSet,
                    displayPart: counterpartPart,
                    matchingParts: aggregatedMatches,
                    contextDescription: "Counterpart: Preview Bundle",
                    onShowSet: {}
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Andrea")
        .toolbar { }
    }
    .modelContainer(container)
}
