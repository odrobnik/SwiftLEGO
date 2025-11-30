import SwiftUI
import SwiftData
#if canImport(BrickCore)
import BrickCore
#endif

struct PartSearchResultRow: View {
    @Environment(\.modelContext) private var modelContext
    let set: BrickSet
    @Bindable var part: Part
    let owningMinifigure: Minifigure?
    let parentChain: [Part]

    private var quantityBinding: Binding<Int> {
        Binding(
            get: { part.quantityHave },
            set: { updateQuantity(to: $0) }
        )
    }

    private var thumbnailSource: Part {
        if part.thumbnailImageURL != nil {
            return part
        }
        return parentChain.last ?? part
    }

    private var totalMissing: Int {
        missingCount(for: part)
    }

    private var totalNeeded: Int {
        part.quantityNeeded
    }

    private var totalHave: Int {
        part.quantityHave
    }

    private var secondaryContextLine: String? {
        var segments: [String] = []

        if let owningMinifigure {
            let name = owningMinifigure.displayName().trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                segments.append("Minifigure: \(name)")
            }
        }

        let parentNames = parentChain
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !parentNames.isEmpty {
            segments.append(parentNames.joined(separator: " › "))
        }

        return segments.isEmpty ? nil : segments.joined(separator: " • ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                PartThumbnail(part: thumbnailSource)

                VStack(alignment: .leading, spacing: 6) {
                    Text(part.name)
                        .font(.headline)

                    let colorName = part.colorName.isEmpty ? "Unknown color" : part.colorName
                    Text("\(part.partID) • \(colorName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .center, spacing: 6) {
                    Text("\(part.quantityHave) of \(part.quantityNeeded)")
                        .font(.title3.bold())
                        .contentTransition(.numericText())
                        .multilineTextAlignment(.center)

                    Stepper("", value: quantityBinding, in: 0...part.quantityNeeded)
                        .labelsHidden()
                }
                .frame(minWidth: 150, alignment: .center)
            }

            HStack(alignment: .center, spacing: 12) {
                Text(set.collection?.name ?? "List")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.12))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                    )

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(set.setNumber) • \(set.name)")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)

                    if let line = secondaryContextLine {
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                markComplete()
            } label: {
                Label("Have All", systemImage: "checkmark.circle.fill")
            }
            .tint(.green)
            .disabled(part.quantityHave >= part.quantityNeeded)
        }
    }

    private func missingCount(for part: Part) -> Int {
        max(part.quantityNeeded - part.quantityHave, 0)
    }

    private func updateQuantity(to newValue: Int) {
        let clamped = max(0, min(newValue, part.quantityNeeded))
        guard clamped != part.quantityHave else { return }

        let applyChange = {
            part.quantityHave = clamped
            part.synchronizeSubparts(to: clamped)
            part.propagateCompletionUpwardsIfNeeded()
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

    private func markComplete() {
        updateQuantity(to: part.quantityNeeded)
    }
}

private struct PartThumbnail: View {
    let part: Part

    var body: some View {
        QuickLookThumbnail(item: part) {
            if let url = part.thumbnailImageURL {
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

    return PartSearchResultRow(
        set: set,
        part: part,
        owningMinifigure: nil,
        parentChain: []
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

    return NavigationStack {
        List {
            Section("Black") {
                PartSearchResultRow(
                    set: directSet,
                    part: directPart,
                    owningMinifigure: nil,
                    parentChain: []
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowSeparator(.hidden)

                PartSearchResultRow(
                    set: counterpartSet,
                    part: counterpartPart.subparts.first ?? counterpartPart,
                    owningMinifigure: nil,
                    parentChain: counterpartPart.subparts.isEmpty ? [] : [counterpartPart]
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

#Preview("Part Result Row – Minifigure Sub-Part") {
    let container = SwiftLEGOModelContainer.preview
    let context = ModelContext(container)

    let view: PartSearchResultRow = {
        let set = BrickSet(setNumber: "70838-1", name: "Queen Watevra's So-Not-Evil Space Palace")
        context.insert(set)

        let minifigure = Minifigure(
            identifier: "tlm198",
            name: "Sweet Mayhem",
            quantityNeeded: 1,
            set: set
        )
        context.insert(minifigure)
        set.minifigures.append(minifigure)

        let assembly = Part(
            partID: "spa0001",
            name: "Helmet Assembly",
            colorID: "1",
            colorName: "White",
            quantityNeeded: 1,
            quantityHave: 0,
            inventorySection: .counterpart,
            minifigure: minifigure
        )
        context.insert(assembly)
        minifigure.parts.append(assembly)

        let subpart = Part(
            partID: "35787pb003",
            name: "Flight Visor",
            colorID: "1",
            colorName: "White",
            quantityNeeded: 1,
            quantityHave: 0,
            minifigure: minifigure,
            parentPart: assembly
        )
        context.insert(subpart)
        assembly.subparts.append(subpart)

        return PartSearchResultRow(
            set: set,
            part: subpart,
            owningMinifigure: minifigure,
            parentChain: [assembly]
        )
    }()

    view
    .padding()
    .modelContainer(container)
}
