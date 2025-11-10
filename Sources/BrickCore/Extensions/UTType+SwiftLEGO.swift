import UniformTypeIdentifiers

public extension UTType {
    static let legoInventory: UTType = {
        if let type = UTType(filenameExtension: "lego", conformingTo: .json) {
            return type
        }
        return UTType(importedAs: "com.swiftlego.inventory")
    }()

    static let brickLinkWantedList: UTType = {
        if let type = UTType(filenameExtension: "xml", conformingTo: .xml) {
            return type
        }
        return UTType(importedAs: "com.swiftlego.bricklink.wantedlist")
    }()
}
