import Foundation
import SwiftData

enum ColorImportUtilities {
    @MainActor
    static func refreshBrickLinkColors(
        modelContext: ModelContext,
        locale: String = "en-us",
        service: BrickLinkColorGuideService = BrickLinkColorGuideService()
    ) async throws -> [BrickColor] {
        let entries = try await service.fetchColorGuide(locale: locale)
        return try persist(entries, in: modelContext)
    }

    @MainActor
    static func persist(
        _ entries: [BrickLinkColorGuideEntry],
        in modelContext: ModelContext
    ) throws -> [BrickColor] {
        let existingColors = try modelContext.fetch(FetchDescriptor<BrickColor>())
        let existingByID = Dictionary(uniqueKeysWithValues: existingColors.map { ($0.brickLinkColorID, $0) })

        var updatedColors: [BrickColor] = []

        let incomingIDs = Set(entries.map { $0.brickLinkColorID })

        // Remove colors no longer present
        for color in existingColors where !incomingIDs.contains(color.brickLinkColorID) {
            modelContext.delete(color)
        }

        for entry in entries.sorted(by: { $0.brickLinkColorID < $1.brickLinkColorID }) {
            if let existing = existingByID[entry.brickLinkColorID] {
                existing.brickLinkName = entry.brickLinkName
                existing.legoColorName = entry.legoColorName
                existing.legoColorID = entry.legoColorID
                existing.hexColor = entry.hexColor
                existing.updatedAt = Date()
                updatedColors.append(existing)
            } else {
                let color = BrickColor(
                    brickLinkColorID: entry.brickLinkColorID,
                    brickLinkName: entry.brickLinkName,
                    legoColorName: entry.legoColorName,
                    legoColorID: entry.legoColorID,
                    hexColor: entry.hexColor
                )
                modelContext.insert(color)
                updatedColors.append(color)
            }
        }

        try modelContext.save()
        return updatedColors
    }
}
