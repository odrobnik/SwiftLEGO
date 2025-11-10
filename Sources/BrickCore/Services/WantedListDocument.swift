import Foundation
import SwiftUI
import UniformTypeIdentifiers
import XMLCoder

public struct WantedListDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.brickLinkWantedList, .xml] }
    public static var writableContentTypes: [UTType] { [.brickLinkWantedList] }

    public var inventory: WantedListInventory

    public init(inventory: WantedListInventory) {
        self.inventory = inventory
    }

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoder = XMLDecoder()
        decoder.trimValueWhitespaces = false
        decoder.shouldProcessNamespaces = false
        self.inventory = try decoder.decode(WantedListInventory.self, from: data)
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = XMLEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let header = XMLHeader(version: 1.0, encoding: "UTF-8", standalone: nil)
        let data = try encoder.encode(
            inventory,
            withRootKey: "INVENTORY",
            header: header
        )
        return .init(regularFileWithContents: data)
    }

    public static func defaultFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "bricklink-wanted-list-\(formatter.string(from: Date())).xml"
    }
}
