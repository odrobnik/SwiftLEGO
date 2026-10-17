import Foundation
import SwiftData
import Testing
@testable import BrickCore

/// Which image a part's closeup loads.
@MainActor
struct PartImageURLTests {
	@Test
	func aStickerSheetsCloseupIsItsMainImageNotTheLegacyThumbnail() throws {
		let context = try makeInMemoryModelContext()
		let sheet = Part(
			partID: "75948stk01",
			name: "Sticker Sheet for Set 75948, Sheet 1",
			colorID: "",
			colorName: "",
			quantityNeeded: 1,
			imageURLString: "https://img.bricklink.com/P/0/75948stk01.jpg",
			fullImageURLString: "https://img.bricklink.com/P/0/75948stk01.jpg"
		)
		context.insert(sheet)

		#expect(sheet.highResolutionImageURL?.absoluteString == "https://img.bricklink.com/ItemImage/PN/0/75948stk01.png")
		#expect(sheet.thumbnailImageURL?.absoluteString == "https://img.bricklink.com/P/0/75948stk01.jpg")
	}

	@Test
	func aStoredMainImageIsKept() throws {
		let context = try makeInMemoryModelContext()
		let brick = Part(
			partID: "3001",
			name: "Brick 2 x 4",
			colorID: "11",
			colorName: "Black",
			quantityNeeded: 1,
			imageURLString: "https://img.bricklink.com/P/11/3001.jpg",
			fullImageURLString: "https://img.bricklink.com/ItemImage/PN/11/3001.png"
		)
		context.insert(brick)

		#expect(brick.highResolutionImageURL?.absoluteString == "https://img.bricklink.com/ItemImage/PN/11/3001.png")
	}

	@Test
	func aNoImagePlaceholderGivesWayToTheImageInThePartsColor() throws {
		let context = try makeInMemoryModelContext()
		let placeholder = "https://img.bricklink.com//static.bricklink.com/clone/img/no_image.png"
		let part = Part(
			partID: "3464",
			name: "Wheel Centre Small",
			colorID: "85",
			colorName: "Dark Bluish Gray",
			quantityNeeded: 1,
			imageURLString: placeholder,
			fullImageURLString: placeholder
		)
		context.insert(part)

		#expect(part.highResolutionImageURL?.absoluteString == "https://img.bricklink.com/ItemImage/PN/85/3464.png")
	}

	@Test
	func anOrderLinesCloseupIsTheMainImageInItsColor() throws {
		let context = try makeInMemoryModelContext()
		let line = OrderPart(
			partID: "14769pb050",
			name: "Tile, Round 2 x 2 with Pattern",
			colorID: "115",
			colorName: "Pearl Gold",
			quantity: 1,
			imageURLString: "https://img.bricklink.com/P/115/14769pb050.jpg"
		)
		let figure = OrderPart(
			itemType: .minifigure,
			partID: "hp194",
			name: "Harry Potter",
			colorID: "0",
			colorName: "",
			quantity: 1,
			imageURLString: "https://img.bricklink.com/M/hp194.jpg"
		)
		context.insert(line)
		context.insert(figure)

		#expect(line.highResolutionImageURL?.absoluteString == "https://img.bricklink.com/ItemImage/PN/115/14769pb050.png")
		#expect(figure.highResolutionImageURL == nil)
	}
}
