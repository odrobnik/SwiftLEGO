import SwiftData
@testable import BrickCore

@MainActor
func makeInMemoryModelContext() throws -> ModelContext {
    let container = try SwiftLEGOModelContainer.makeContainer(inMemory: true)
    return ModelContext(container)
}
