import Foundation
import UniformTypeIdentifiers
import SwiftUI

public struct InventorySnapshotDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.legoInventory, .json] }
    public static var writableContentTypes: [UTType] { [.legoInventory] }

    public var snapshot: InventorySnapshot

    public init(snapshot: InventorySnapshot) {
        self.snapshot = snapshot
    }

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoder = JSONDecoder()
        self.snapshot = try decoder.decode(InventorySnapshot.self, from: data)
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        return .init(regularFileWithContents: data)
    }

    public static func defaultFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "inventory-snapshot-\(formatter.string(from: Date())).lego"
    }
}
