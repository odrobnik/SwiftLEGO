import SwiftUI
import BrickCore

private struct BrickLinkServiceKey: EnvironmentKey {
    /// One service for the whole app. It holds no per-caller state, and a view that
    /// created its own allocated a new actor every time SwiftUI rebuilt the view value.
    static let defaultValue = BrickLinkService()
}

extension EnvironmentValues {
    var brickLinkService: BrickLinkService {
        get { self[BrickLinkServiceKey.self] }
        set { self[BrickLinkServiceKey.self] = newValue }
    }

    /// Whether the enclosing parts list only shows parts that are still missing, so a
    /// row can animate a part that becomes complete out of the list.
    @Entry var isFilteringMissingParts = false
}
