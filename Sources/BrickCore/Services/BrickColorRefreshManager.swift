import Foundation
import SwiftData

@MainActor
final class BrickColorRefreshManager {
    static let shared = BrickColorRefreshManager()

    private let userDefaults: UserDefaults
    private let service: BrickLinkColorGuideService
    private let refreshInterval: TimeInterval
    private let lastRefreshDateKey = "BrickColorRefreshManager.lastRefreshDate"

    private var isRefreshing = false

    init(
        userDefaults: UserDefaults = .standard,
        service: BrickLinkColorGuideService = BrickLinkColorGuideService(),
        refreshInterval: TimeInterval = 7 * 24 * 60 * 60
    ) {
        self.userDefaults = userDefaults
        self.service = service
        self.refreshInterval = refreshInterval
    }

    func refreshIfNeeded(using modelContext: ModelContext, locale: Locale = .current) async {
        guard !isRefreshing else { return }

        var descriptor = FetchDescriptor<BrickColor>()
        descriptor.fetchLimit = 1
        let existingColors = (try? modelContext.fetch(descriptor)) ?? []
        let hasExistingColors = !existingColors.isEmpty

        let lastRefreshDate = userDefaults.object(forKey: lastRefreshDateKey) as? Date
        let isStale: Bool
        if let lastRefreshDate {
            isStale = Date().timeIntervalSince(lastRefreshDate) >= refreshInterval
        } else {
            isStale = true
        }

        guard !hasExistingColors || isStale else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let localeIdentifier = Self.localeIdentifier(for: locale)
            _ = try await ColorImportUtilities.refreshBrickLinkColors(
                modelContext: modelContext,
                locale: localeIdentifier,
                service: service
            )
            userDefaults.set(Date(), forKey: lastRefreshDateKey)
        } catch {
            #if DEBUG
            print("BrickColorRefreshManager failed to refresh colors: \(error)")
            #endif
        }
    }

    private static func localeIdentifier(for locale: Locale) -> String {
        let normalized = locale.identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        let components = normalized.split(separator: "-")
        guard let language = components.first else {
            return "en-us"
        }

        let region = components.dropFirst().first ?? Substring("us")
        return "\(language)-\(region)"
    }
}
