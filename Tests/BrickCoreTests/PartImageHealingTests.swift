import Foundation
import SwiftData
import Testing
@testable import BrickCore

/// Serialized because `ImageServerStub` serves its images globally.
@Suite(.serialized)
@MainActor
struct PartImageHealingTests {
	private static let oldThumbnail = URL(string: "https://img.bricklink.com/ItemImage/PT/157/14769pb328.t1.png")!
	private static let newThumbnail = URL(string: "https://img.bricklink.com/ItemImage/PT/157/14769pb0328.t1.png")!

	// MARK: - Locating

	@Test
	func aRenumberedPartIsFoundUnderItsPaddedNumber() async throws {
		let locator = try makeLocator(serving: [Self.newThumbnail: ImageServerStub.png])

		let itemNumber = await locator.currentItemNumber(for: "14769pb328", colorID: "157")

		#expect(itemNumber == "14769pb0328")
		#expect(ImageServerStub.requestedURLs == [Self.oldThumbnail, Self.newThumbnail])
	}

	@Test
	func aPartWhoseImageOnlyMovedKeepsItsNumber() async throws {
		let thumbnail = try #require(URL(string: "https://img.bricklink.com/ItemImage/PT/11/3001.t1.png"))
		let locator = try makeLocator(serving: [thumbnail: ImageServerStub.png])

		#expect(await locator.currentItemNumber(for: "3001", colorID: "11") == "3001")
	}

	@Test
	func aPartWithNoImageAnywhereIsAskedAboutOnce() async throws {
		let locator = try makeLocator()

		#expect(await locator.currentItemNumber(for: "14769pb328", colorID: "157") == nil)
		let requestCount = ImageServerStub.requestedURLs.count

		#expect(await locator.currentItemNumber(for: "14769pb328", colorID: "157") == nil)
		#expect(ImageServerStub.requestedURLs.count == requestCount, "A part already found missing should not be looked up again.")
	}

	@Test
	func aPageThatIsNotAnImageProvesNothing() async throws {
		let challenge = Data("<html><body>Checking your browser…</body></html>".utf8)
		let locator = try makeLocator(serving: [Self.newThumbnail: challenge])

		#expect(await locator.currentItemNumber(for: "14769pb328", colorID: "157") == nil)
	}

	@Test
	func aPartWithoutAColorIsNotLookedUp() async throws {
		let locator = try makeLocator()

		#expect(await locator.currentItemNumber(for: "14769pb328", colorID: "") == nil)
		#expect(ImageServerStub.requestedURLs.isEmpty)
	}

	@Test
	func aMissingImageIsNotRequestedTwice() async throws {
		let cache = try makeCache()

		for _ in 0..<2 {
			let error = await #expect(throws: ThumbnailCacheError.self) {
				_ = try await cache.data(for: Self.oldThumbnail)
			}
			#expect(error?.isNotFound == true)
		}

		#expect(ImageServerStub.requestedURLs == [Self.oldThumbnail])
	}

	// MARK: - Healing

	@Test
	func healingMovesEveryPartAndOrderLineWithTheOldNumber() async throws {
		let context = try makeInMemoryModelContext()
		let viewed = Self.tile(colorID: "157")
		let elsewhere = Self.tile(colorID: "157")
		let otherColor = Self.tile(colorID: "1")
		let unrelated = Part(partID: "3001", name: "Brick 2 x 4", colorID: "157", colorName: "Medium Lavender", quantityNeeded: 1)
		let orderLine = OrderPart(
			partID: "14769pb328",
			name: "Tile, Round 2 x 2 with Seat Cushion Pattern",
			colorID: "157",
			colorName: "Medium Lavender",
			quantity: 1,
			imageURLString: "https://img.bricklink.com/P/157/14769pb328.jpg"
		)
		for part in [viewed, elsewhere, otherColor, unrelated] {
			context.insert(part)
		}
		context.insert(orderLine)
		try context.save()

		let locator = try makeLocator(serving: [Self.newThumbnail: ImageServerStub.png])
		let healedURL = await PartImageHealing.healThumbnail(of: viewed, in: context, locator: locator)

		#expect(healedURL == Self.newThumbnail)

		for part in [viewed, elsewhere] {
			#expect(part.partID == "14769pb0328")
			#expect(part.thumbnailImageURL == Self.newThumbnail)
			#expect(part.fullImageURLString == "https://img.bricklink.com/ItemImage/PN/157/14769pb0328.png")
			#expect(part.partURLString == "https://www.bricklink.com/v2/catalog/catalogitem.page?P=14769pb0328&idColor=157")
		}

		// BrickLink renumbers the item, so every color of it moves.
		#expect(otherColor.partID == "14769pb0328")
		#expect(otherColor.imageURLString == "https://img.bricklink.com/ItemImage/PT/1/14769pb0328.t1.png")

		#expect(orderLine.partID == "14769pb0328")
		#expect(orderLine.imageURL == Self.newThumbnail)

		#expect(unrelated.partID == "3001")
		#expect(!context.hasChanges, "Healing should save what it moved.")
	}

	@Test
	func aPartBrickLinkHasNoImageForIsLeftAlone() async throws {
		let context = try makeInMemoryModelContext()
		let part = Self.tile(colorID: "157")
		context.insert(part)
		try context.save()

		let locator = try makeLocator()
		let healedURL = await PartImageHealing.healThumbnail(of: part, in: context, locator: locator)

		#expect(healedURL == nil)
		#expect(part.partID == "14769pb328")
		#expect(part.imageURLString == "https://img.bricklink.com/P/157/14769pb328.jpg")
	}

	// MARK: - Helpers

	/// A round tile as an import from before BrickLink padded its pattern number stored it.
	private static func tile(colorID: String) -> Part {
		Part(
			partID: "14769pb328",
			name: "Tile, Round 2 x 2 with Seat Cushion Pattern",
			colorID: colorID,
			colorName: "Medium Lavender",
			quantityNeeded: 2,
			imageURLString: "https://img.bricklink.com/P/\(colorID)/14769pb328.jpg",
			fullImageURLString: "https://img.bricklink.com/ItemImage/PN/\(colorID)/14769pb328.png",
			partURLString: "https://www.bricklink.com/v2/catalog/catalogitem.page?P=14769pb328&idColor=\(colorID)"
		)
	}

	private func makeLocator(serving images: [URL: Data] = [:]) throws -> PartImageLocator {
		PartImageLocator(thumbnails: try makeCache(serving: images))
	}

	/// A cache of its own, on disk in a fresh directory, in front of the stub server.
	private func makeCache(serving images: [URL: Data] = [:]) throws -> ThumbnailCacheManager {
		ImageServerStub.reset(serving: images)

		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("PartImageHealingTests-\(UUID().uuidString)", isDirectory: true)

		return ThumbnailCacheManager(session: ImageServerStub.makeSession(), cacheDirectory: directory)
	}
}
