import SwiftUI
import SwiftData
import BrickCore

/// Presentation and refresh state shared by the cells of a set grid. The screen owns
/// it and puts it in the environment, so each cell reads what it needs itself, and a
/// refresh starting or finishing updates that cell rather than re-running the grid.
@MainActor
@Observable
final class SetGridModel {
    struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var setBeingEdited: BrickSet?
    var labelPrintTarget: BrickSet?
    var alert: AlertMessage?
    private var refreshingSetIDs: Set<PersistentIdentifier> = []

    func isRefreshing(_ set: BrickSet) -> Bool {
        refreshingSetIDs.contains(set.persistentModelID)
    }

    func refresh(_ set: BrickSet, modelContext: ModelContext, service: BrickLinkService) {
        let identifier = set.persistentModelID
        guard refreshingSetIDs.insert(identifier).inserted else { return }

        Task {
            defer { refreshingSetIDs.remove(identifier) }

            do {
                try await SetImportUtilities.refreshSetFromBrickLink(
                    set: set,
                    modelContext: modelContext,
                    service: service
                )
            } catch {
                alert = AlertMessage(title: "Refresh Failed", message: error.localizedDescription)
            }
        }
    }

    func delete(_ set: BrickSet, from modelContext: ModelContext) {
        modelContext.delete(set)
        try? modelContext.save()
    }
}

extension View {
    /// Provides `model` to the set grid cells and presents the sheets and alerts it asks for.
    func setGridPresentations(for model: SetGridModel) -> some View {
        modifier(SetGridPresentations(model: model))
    }
}

private struct SetGridPresentations: ViewModifier {
    @Bindable var model: SetGridModel

    func body(content: Content) -> some View {
        content
            .environment(model)
            .sheet(item: $model.setBeingEdited) { set in
                SetEditView(set: set)
            }
            .sheet(item: $model.labelPrintTarget) { set in
                LabelPrintSheet(brickSet: set)
            }
            .alert(item: $model.alert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
    }
}

/// Where a set grid reads its sets from.
enum SetGridSource {
    case list(CollectionList)
    case sets([BrickSet])

    var sets: [BrickSet] {
        switch self {
        case .list(let list):
            list.sets
        case .sets(let sets):
            sets
        }
    }
}

/// One titled group of sets in a set grid.
struct SetSection: Identifiable {
    let id: [String]
    let title: String
    let sets: [BrickSet]
}

extension SetSection {
    private static let otherTitle = "Other"

    /// Groups sets by their full category path, with uncategorized sets last.
    static func byCategory(_ sets: [BrickSet]) -> [SetSection] {
        let uncategorized = [CategoryConstants.uncategorizedTitle]

        return Dictionary(grouping: sets) { set in
            set.normalizedCategoryPath(uncategorizedTitle: CategoryConstants.uncategorizedTitle)
        }
        .map { path, sets in
            SetSection(id: path, title: path.joined(separator: " / "), sets: sets.sorted(by: BrickSet.displayOrder))
        }
        .sorted { lhs, rhs in
            let lhsIsUncategorized = lhs.id == uncategorized
            let rhsIsUncategorized = rhs.id == uncategorized
            if lhsIsUncategorized != rhsIsUncategorized {
                return rhsIsUncategorized
            }
            return lhs.id.lexicographicallyPrecedes(rhs.id)
        }
    }

    /// Groups sets by the part of their category path below `categoryPath`, with the
    /// sets that sit directly in that category last, under "Other".
    static func byCategory(_ sets: [BrickSet], below categoryPath: [String]) -> [SetSection] {
        let parentPath = CategoryConstants.pathBelowRoot(categoryPath)

        return Dictionary(grouping: sets) { set in
            remainingPath(of: set, below: parentPath).joined(separator: " / ")
        }
        .map { key, sets in
            SetSection(id: [key], title: key.isEmpty ? otherTitle : key, sets: sets.sorted(by: BrickSet.displayOrder))
        }
        .sorted { lhs, rhs in
            if lhs.title == otherTitle {
                return false
            }
            if rhs.title == otherTitle {
                return true
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private static func remainingPath(of set: BrickSet, below parentPath: [String]) -> [String] {
        let path = set.normalizedCategoryPath(uncategorizedTitle: CategoryConstants.uncategorizedTitle)
        guard path.count > parentPath.count else { return [] }
        return path.starts(with: parentPath) ? Array(path.dropFirst(parentPath.count)) : path
    }
}

/// The category sections of a set grid, stacked lazily.
struct SetSectionStack: View {
    let sections: [SetSection]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(sections) { section in
                SetCategorySection(section: section)
            }
        }
        .padding(.vertical)
    }
}

/// A titled grid of set cards.
struct SetCategorySection: View {
    private static let columns = [
        GridItem(.adaptive(minimum: 220), spacing: 16)
    ]

    let section: SetSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.title3.weight(.semibold))
                .padding(.horizontal)

            LazyVGrid(columns: Self.columns, spacing: 16) {
                ForEach(section.sets) { set in
                    SetGridCell(set: set)
                }
            }
            .padding(.horizontal)
        }
    }
}

/// A set card that opens the set, with a context menu to view, refresh, print, edit
/// or delete it.
struct SetGridCell: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.brickLinkService) private var brickLinkService
    @Environment(SetGridModel.self) private var model
    let set: BrickSet

    var body: some View {
        NavigationLink(value: set) {
            SetCardView(brickSet: set)
                .overlay(alignment: .topTrailing) {
                    if model.isRefreshing(set) {
                        ProgressView()
                            .controlSize(.mini)
                            .padding(6)
                    }
                }
        }
        .buttonStyle(.plain)
        .contextMenu {
            QuickLookMenuButton(item: set) {
                Label("View Set", systemImage: "eye")
            }
            Button("Refresh from BrickLink", systemImage: "arrow.clockwise") {
                model.refresh(set, modelContext: modelContext, service: brickLinkService)
            }
            .disabled(model.isRefreshing(set))
            Button("Print Label…", systemImage: "printer") {
                model.labelPrintTarget = set
            }
            Button("Edit", systemImage: "slider.horizontal.3") {
                model.setBeingEdited = set
            }
            Button(role: .destructive) {
                model.delete(set, from: modelContext)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
