import XCTest
@testable import BrickCore

final class BrickLinkInventoryServiceTests: XCTestCase {

	func testBrickLinkInventoryMarkdownConversion() async throws {
		let url = URL(string: "https://www.bricklink.com/catalogItemInv.asp?S=10294-1")!
		let converter = HTML💡Markdown(url: url)

		let markdown = try await converter.markdown()

		XCTAssertTrue(markdown.contains("| **Image**"))
		XCTAssertTrue(markdown.contains("| ------- |"))
		XCTAssertTrue(markdown.contains("[87994](https://www.bricklink.com/v2/catalog/catalogitem.page?P=87994&idColor=11)"))
	}

	func testFetchInventoryParsesParts() async throws {
		let service = BrickLinkInventoryService()
		let inventory = try await service.fetchInventory(for: "10294-1")

		XCTAssertEqual(inventory.setNumber.lowercased(), "10294-1".lowercased())
		XCTAssertFalse(inventory.parts.isEmpty)
		XCTAssertEqual(inventory.name, "Titanic")
		XCTAssertEqual(inventory.thumbnailURL, URL(string: "https://img.bricklink.com/SL/10294-1.jpg"))

		let targetPart = inventory.parts.first { $0.partID == "87994" && $0.colorID == "11" }
		if targetPart == nil {
			let sample = inventory.parts.prefix(5).map { "\($0.partID)-\($0.colorID)" }.joined(separator: ", ")
			XCTFail("Expected to find part 87994 in color 11. Sample parts: \(sample)")
		}

		XCTAssertEqual(targetPart?.colorName, "Black")
		XCTAssertEqual(targetPart?.name, "Bar 3L (Bar Arrow)")
	}

	func testFetchInventoryParsesMinifigures() async throws {
		let service = BrickLinkInventoryService()
		let inventory = try await service.fetchInventory(for: "41050-1")

		let minifigure = inventory.minifigures.first { $0.identifier.lowercased() == "dp001" }
		XCTAssertNotNil(minifigure)
		XCTAssertEqual(minifigure?.quantity, 1)
		XCTAssertTrue(minifigure?.name.hasPrefix("Ariel, Mermaid (Light Nougat)") ?? false)
		XCTAssertFalse(minifigure?.parts.isEmpty ?? true)
	}
}
