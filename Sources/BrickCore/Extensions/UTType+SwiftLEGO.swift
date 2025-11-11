import UniformTypeIdentifiers

public extension UTType {
    static let legoInventory: UTType = {
        let identifier = "com.swiftlego.inventory"
        if let declaredType = UTType(identifier) {
            return declaredType
        }
        if let extensionType = UTType(filenameExtension: "lego") {
            // Matches Files.app / UIDocumentPicker when the custom type is not registered.
            return extensionType
        }
        return UTType(importedAs: identifier)
    }()

    static let brickLinkWantedList: UTType = {
        if let type = UTType(filenameExtension: "xml", conformingTo: .xml) {
            return type
        }
        return UTType(importedAs: "com.swiftlego.bricklink.wantedlist")
    }()
}
