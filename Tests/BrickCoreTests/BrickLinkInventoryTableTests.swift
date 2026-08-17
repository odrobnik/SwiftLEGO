import Foundation
import Testing
@testable import BrickCore

/// Offline coverage for the `catalogitem.page` / `catalogitem_invtab.page` pair
/// that replaced the JavaScript-challenged `catalogItemInv.asp` endpoint.
struct BrickLinkInventoryTableTests {

	private static func fixture(_ name: String) throws -> Data {
		let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
		let fixturesDirectory = testsDirectory.deletingLastPathComponent().appendingPathComponent("Fixtures")

		return try Data(contentsOf: fixturesDirectory.appendingPathComponent(name))
	}

	private static func inventoryTable() async throws -> BrickLinkInventoryTable {
		try await BrickLinkInventoryTable.parse(
			html: fixture("bricklink-invtab-43245-1.html"),
			baseURL: BrickLinkInventoryTable.url(idItem: "240248", itemNumber: "43245-1")
		)
	}

	// MARK: - Catalog page

	@Test
	func catalogPageResolvesItemIdAndMetadata() async throws {
		let url = BrickLinkCatalogItemPage.url(for: .set, number: "43245-1")
		let page = try await BrickLinkCatalogItemPage.parse(
			html: Self.fixture("bricklink-catalogitem-43245-1.html"),
			baseURL: url
		)

		#expect(page.idItem == "240248")
		#expect(page.name == "The Magical Madrigal House")
		#expect(page.thumbnailURL?.absoluteString.contains("43245-1") == true)
		#expect(page.categories.map(\.name) == ["Sets", "Disney", "Encanto"])
		#expect(page.categories.last?.id == "878.1168")
	}

	@Test
	func catalogPageURLUsesItemTypeParameter() {
		#expect(
			BrickLinkCatalogItemPage.url(for: .set, number: "43245-1").absoluteString
				== "https://www.bricklink.com/v2/catalog/catalogitem.page?S=43245-1"
		)
		#expect(
			BrickLinkCatalogItemPage.url(for: .minifigure, number: "dis170").absoluteString
				== "https://www.bricklink.com/v2/catalog/catalogitem.page?M=dis170"
		)
	}

	@Test
	func minifigureCatalogPageCarriesNamedCategories() async throws {
		let url = BrickLinkCatalogItemPage.url(for: .minifigure, number: "dis170")
		let page = try await BrickLinkCatalogItemPage.parse(
			html: Self.fixture("bricklink-catalogitem-dis170.html"),
			baseURL: url
		)

		#expect(page.idItem == "241442")
		#expect(page.name == "Abuela Alma Madrigal - Light Bluish Gray Hair")
		#expect(page.categories.map(\.name) == ["Minifigures", "Disney", "Encanto"])
	}

	// MARK: - Inventory table

	@Test
	func inventoryTableSeparatesPartsFromMinifigures() async throws {
		let table = try await Self.inventoryTable()

		#expect(table.parts.count == 619)
		#expect(table.minifigures.count == 7)
		#expect(
			table.minifigures.map(\.itemNumber)
				== ["dis170", "dis166", "dis169", "dis168", "dis154", "dis167", "dis117"]
		)
	}

	@Test
	func inventoryTableReadsSectionsFromRowClasses() async throws {
		let table = try await Self.inventoryTable()
		let sections = Set(table.parts.map(\.section))

		#expect(sections.contains(.regular))
		#expect(sections.contains(.extra))
		#expect(sections.contains(.counterpart))

		// The trailing summary table repeats the section labels and must not
		// contribute rows of its own.
		#expect(table.parts.allSatisfy { !$0.itemNumber.isEmpty })
	}

	@Test
	func colouredPartRowCarriesColourAndImagery() async throws {
		let table = try await Self.inventoryTable()

		let bar = try #require(table.parts.first { $0.itemNumber == "32828" && $0.colorID == "11" })

		#expect(bar.quantity == 4)
		#expect(bar.name == "Bar 1L with 1 x 1 Round Plate with Hollow Stud")
		#expect(bar.description == "Black Bar 1L with 1 x 1 Round Plate with Hollow Stud")
		#expect(bar.idItem == "157810")
		#expect(bar.hasOwnInventory == false)
		#expect(bar.imageURL?.absoluteString == "https://img.bricklink.com/ItemImage/PT/11/32828.t1.png")
		#expect(bar.itemURL?.absoluteString.contains("catalogitem.page?P=32828") == true)
	}

	@Test
	func uncolouredPartRowHasNoColourID() async throws {
		let table = try await Self.inventoryTable()

		let sticker = try #require(table.parts.first { $0.itemNumber == "43245stk01" })

		#expect(sticker.colorID == "")
		#expect(sticker.quantity == 1)
	}

	@Test
	func partWithOwnInventoryIsFlagged() async throws {
		let table = try await Self.inventoryTable()

		let assembly = try #require(table.parts.first { $0.itemNumber == "4592c05" })

		#expect(assembly.hasOwnInventory)
		#expect(assembly.idItem == "48558")
		#expect(assembly.colorID == "86")
	}

	@Test
	func minifigureRowsAreFlaggedAsHavingInventories() async throws {
		let table = try await Self.inventoryTable()

		let abuela = try #require(table.minifigures.first { $0.itemNumber == "dis170" })

		#expect(abuela.quantity == 1)
		#expect(abuela.name == "Abuela Alma Madrigal - Light Bluish Gray Hair")
		#expect(abuela.hasOwnInventory)
		#expect(abuela.idItem == "241442")
	}

	@Test
	func inventoryTableURLTargetsTheUnchallengedEndpoint() {
		let url = BrickLinkInventoryTable.url(idItem: "240248", itemNumber: "43245-1")

		#expect(url.absoluteString.contains("/v2/catalog/catalogitem_invtab.page"))
		#expect(url.absoluteString.contains("idItem=240248"))
		#expect(url.absoluteString.contains("itemNoSeq=43245-1"))
	}

	// MARK: - Derived values

	@Test
	func colourNameIsTheDescriptionMinusTheItemName() {
		#expect(
			BrickLinkInventoryService.colorName(
				description: "Black Bar 1L with 1 x 1 Round Plate with Hollow Stud",
				name: "Bar 1L with 1 x 1 Round Plate with Hollow Stud"
			) == "Black"
		)

		// A part name that also appears inside the color name.
		#expect(
			BrickLinkInventoryService.colorName(
				description: "Light Bluish Gray Antenna Small Base with Light Bluish Gray Lever (4592 / 4593)",
				name: "Antenna Small Base with Light Bluish Gray Lever (4592 / 4593)"
			) == "Light Bluish Gray"
		)

		// Uncolored items repeat the name verbatim.
		#expect(
			BrickLinkInventoryService.colorName(
				description: "Sticker Sheet for Set 43245, Sheet 1",
				name: "Sticker Sheet for Set 43245, Sheet 1"
			) == ""
		)
	}

	@Test
	func fullSizeImageURLSwapsThumbnailCodeAndSuffix() {
		#expect(
			BrickLinkInventoryService.fullSizeImageURL(
				from: URL(string: "https://img.bricklink.com/ItemImage/PT/11/32828.t1.png")
			)?.absoluteString == "https://img.bricklink.com/ItemImage/PN/11/32828.png"
		)

		#expect(
			BrickLinkInventoryService.fullSizeImageURL(
				from: URL(string: "https://img.bricklink.com/ItemImage/MT/0/dis170.t1.png")
			)?.absoluteString == "https://img.bricklink.com/ItemImage/MN/0/dis170.png"
		)

		#expect(BrickLinkInventoryService.fullSizeImageURL(from: nil) == nil)
	}
}
