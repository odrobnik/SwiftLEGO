import SwiftUI
import SwiftData

struct MinifigureSearchResultRow: View {
    @Environment(\.modelContext) private var modelContext
    let set: BrickSet
    @Bindable var minifigure: Minifigure
    let onShowSet: (() -> Void)?

    private var missingCount: Int {
        max(minifigure.quantityNeeded - minifigure.quantityHave, 0)
    }

    private var quantityBinding: Binding<Int> {
        Binding(
            get: { minifigure.quantityHave },
            set: { updateQuantity(to: $0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                MinifigureThumbnail(url: minifigure.imageURL)

                VStack(alignment: .leading, spacing: 6) {
                    Text(minifigure.name)
                        .font(.headline)

                    Text(minifigure.displayIdentifierWithInstance)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .center, spacing: 6) {
                    Text("\(minifigure.quantityHave) of \(minifigure.quantityNeeded)")
                        .font(.title3.bold())
                        .contentTransition(.numericText())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    Stepper("", value: quantityBinding, in: 0...max(minifigure.quantityNeeded, 0))
                        .labelsHidden()
                }
                .frame(width: 150, alignment: .trailing)
            }

            HStack(alignment: .center, spacing: 12) {
                Text("Missing ^[\(missingCount) minifigure](inflect: true) • Need \(minifigure.quantityNeeded), have \(minifigure.quantityHave)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(missingCount > 0 ? .orange : .green)

                Spacer()

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                markComplete()
            } label: {
                Label("Have All", systemImage: "checkmark.circle.fill")
            }
            .tint(.green)
            .disabled(minifigure.quantityHave >= minifigure.quantityNeeded)
        }
    }

    private func updateQuantity(to newValue: Int) {
        let clamped = max(0, min(newValue, minifigure.quantityNeeded))
        guard clamped != minifigure.quantityHave else { return }

        let applyChange = {
            minifigure.quantityHave = clamped
            try? modelContext.save()
        }

        if clamped >= minifigure.quantityNeeded {
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
        updateQuantity(to: minifigure.quantityNeeded)
    }
}

private struct MinifigureThumbnail: View {
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
                    }
                }
                .background(.white)
            } else {
                placeholder
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
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

#Preview("Minifigure Result Row") {
    let container = SwiftLEGOModelContainer.preview
    let context = ModelContext(container)
    let set = try! context.fetch(FetchDescriptor<BrickSet>()).first!
    let figure: Minifigure
    if let existing = try! context.fetch(FetchDescriptor<Minifigure>()).first {
        figure = existing
    } else {
        let newFigure = Minifigure(
            identifier: "hp001",
            name: "Preview Minifigure",
            quantityNeeded: 1,
            quantityHave: 0,
            set: set
        )
        context.insert(newFigure)
        set.minifigures.append(newFigure)
        figure = newFigure
    }

    return MinifigureSearchResultRow(
        set: set,
        minifigure: figure,
        onShowSet: nil
    )
    .padding()
    .modelContainer(container)
}
