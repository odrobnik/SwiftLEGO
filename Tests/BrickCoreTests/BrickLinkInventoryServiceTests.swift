import Foundation
import Testing
@testable import BrickCore

struct BrickLinkInventoryServiceTests {

	@Test
	func brickLinkInventoryMarkdownConversion() async throws {
		let url = URL(string: "https://www.bricklink.com/catalogItemInv.asp?S=10294-1")!
		let converter = HTML💡Markdown(url: url)

		let markdown = try await converter.markdown()

		#expect(markdown.contains("| **Image**"))
		#expect(markdown.contains("| ------- |"))
		#expect(markdown.contains("[87994](https://www.bricklink.com/v2/catalog/catalogitem.page?P=87994&idColor=11)"))
	}

	@Test
	func fetchInventoryParsesParts() async throws {
		let service = BrickLinkInventoryService()
		let inventory = try await service.fetchInventory(for: "10294-1")

		#expect(inventory.setNumber.lowercased() == "10294-1")
		#expect(!inventory.parts.isEmpty)
		#expect(inventory.name == "Titanic")
		#expect(inventory.thumbnailURL == URL(string: "https://img.bricklink.com/SL/10294-1.jpg"))

		let targetPart = try #require(
			inventory.parts.first { $0.partID == "87994" && $0.colorID == "11" },
			"Expected to find part 87994 in color 11."
		)

		#expect(targetPart.colorName == "Black")
		#expect(targetPart.name == "Bar 3L (Bar Arrow)")
	}

	@Test
	func fetchInventoryParsesMinifigures() async throws {
		let service = BrickLinkInventoryService()
		let inventory = try await service.fetchInventory(for: "41050-1")

		let minifigure = try #require(
			inventory.minifigures.first { $0.identifier.lowercased() == "dp001" },
			"Expected to find minifigure dp001."
		)

		#expect(minifigure.quantity == 1)
		#expect(minifigure.name.hasPrefix("Ariel, Mermaid (Light Nougat)"))
		#expect(!minifigure.parts.isEmpty)
		#expect(
			minifigure.categories.map(\.name) == ["Minifigures", "Disney", "Disney Princess", "The Little Mermaid"]
		)
	}

	@Test
	func fetchInventoryFor75965() async throws {
		let service = BrickLinkInventoryService()
		let inventory = try await service.fetchInventory(for: "75965-1")

		#expect(inventory.setNumber.lowercased() == "75965-1")
		#expect(!inventory.parts.isEmpty)
	}

	@Test
	func fetchInventoryFor41314IncludesSubparts() async throws {
		let service = BrickLinkInventoryService()
		let inventory = try await service.fetchInventory(for: "41314-1")

		let accessories = try #require(
			inventory.parts.first { part in
				part.partID == "93082" && part.colorID == "42"
			},
			"Expected to find accessory multipack part 93082."
		)

		#expect(accessories.quantity == 1)
		#expect(accessories.inventoryURL != nil)
		#expect(!accessories.subparts.isEmpty)
		#expect(accessories.subparts.first { $0.partID == "93082g" }?.quantity == 3)
		#expect(accessories.subparts.first { $0.partID == "93082i" }?.quantity == 3)

		let sprue = try #require(
			inventory.parts.first { $0.partID == "3742sprue" },
			"Expected to find sprue 3742sprue."
		)

		#expect(sprue.subparts.count == 1)
		#expect(sprue.subparts.first?.partID == "3742")
		#expect(sprue.subparts.first?.quantity == 4)
	}

	@Test
	func inventorySnapshotLegacyDecoding() throws {
		struct LegacyInventorySnapshot: Codable {
			struct SetSnapshot: Codable {
				struct PartSnapshot: Codable {
					let partID: String
					let colorID: String
					let quantityHave: Int
					let inventorySection: String?
					let subparts: [PartSnapshot]?
				}

				struct MinifigureSnapshot: Codable {
					let identifier: String
					let quantityHave: Int
					let parts: [PartSnapshot]
				}

				let setNumber: String
				let parts: [PartSnapshot]
				let minifigures: [MinifigureSnapshot]?
			}

			let sets: [SetSnapshot]
		}

		let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		let fixturesDirectory = testsDirectory.deletingLastPathComponent().appendingPathComponent("Fixtures")
		let fileURL = fixturesDirectory.appendingPathComponent("inventory-snapshot.json")

		let data = try Data(contentsOf: fileURL)
		let snapshot = try JSONDecoder().decode(LegacyInventorySnapshot.self, from: data)

		#expect(!snapshot.sets.isEmpty)
	}
}
