import UniformTypeIdentifiers
import Testing
@testable import BrickCore

struct UTTypeTests {
    @Test
    func legoInventoryUsesLegoExtension() {
        #expect(
            UTType.legoInventory.preferredFilenameExtension == "lego",
            "Inventory snapshots must keep the .lego extension so fileImporter filters include them."
        )
    }
}
