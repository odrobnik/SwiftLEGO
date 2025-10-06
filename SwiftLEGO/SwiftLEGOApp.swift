import SwiftUI
import SwiftData

@main
struct SwiftLEGOApp: App {
    private let modelContainer = SwiftLEGOModelContainer.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
        }
    }
}
