import Foundation

enum CategoryConstants {
    /// The title of the root of the category tree in the sidebar.
    static let rootCategoryTitle: String = "Sets"
    static let uncategorizedTitle: String = "Uncategorized"

    /// `path` without the leading root entry that sidebar category paths start with.
    static func pathBelowRoot(_ path: [String]) -> [String] {
        path.first == rootCategoryTitle ? Array(path.dropFirst()) : path
    }
}
