import Foundation
import SwiftData

enum SwiftLEGOModelContainer {
    static let shared: ModelContainer = {
        do {
            return try createContainer()
        } catch {
            fatalError("Unable to set up SwiftData container: \(error)")
        }
    }()

    static let preview: ModelContainer = {
        do {
            return try createContainer(inMemory: true, preloadSampleData: true)
        } catch {
            fatalError("Unable to set up preview container: \(error)")
        }
    }()

    private static func createContainer(
        inMemory: Bool = false,
        preloadSampleData: Bool = false
    ) throws -> ModelContainer {
        let schema = Schema([
            CollectionList.self,
            BrickSet.self,
            Part.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        let container = try ModelContainer(for: schema, configurations: configuration)

        if preloadSampleData {
            let context = ModelContext(container)
            prefillSampleData(in: context)
        }

        return container
    }

    private static func prefillSampleData(in context: ModelContext) {
        let sampleList = CollectionList(name: "Sample Collection")
        let sampleSet = BrickSet(
            setNumber: "10220",
            name: "Volkswagen T1 Camper Van",
            thumbnailURLString: nil,
            parts: [
                Part(partID: "3001", colorID: "5", quantityNeeded: 24, quantityHave: 12),
                Part(partID: "3020", colorID: "1", quantityNeeded: 40, quantityHave: 8)
            ],
            collection: sampleList
        )

        sampleList.sets = [sampleSet]
        context.insert(sampleList)
        try? context.save()
    }
}
