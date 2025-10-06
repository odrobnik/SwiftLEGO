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
                Part(
                    partID: "3001",
                    name: "Brick 2 x 4",
                    colorID: "5",
                    colorName: "Red",
                    quantityNeeded: 24,
                    quantityHave: 12,
                    imageURLString: nil,
                    partURLString: nil
                ),
                Part(
                    partID: "3020",
                    name: "Plate 2 x 4",
                    colorID: "1",
                    colorName: "White",
                    quantityNeeded: 40,
                    quantityHave: 8,
                    imageURLString: nil,
                    partURLString: nil
                )
            ],
            collection: sampleList
        )

        sampleList.sets = [sampleSet]
        context.insert(sampleList)
        try? context.save()
    }
}
