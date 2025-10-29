import UniformTypeIdentifiers

public extension UTType {
    static let legoInventory: UTType = {
        if let type = UTType(filenameExtension: "lego", conformingTo: .json) {
            return type
        }
        return UTType(importedAs: "com.swiftlego.inventory")
    }()
}
