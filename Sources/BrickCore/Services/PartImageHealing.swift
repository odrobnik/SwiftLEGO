import Foundation
import ImageIO
import SwiftData

/// Finds where BrickLink keeps a part's image once its stored URL stops
/// answering.
///
/// The part's own number is tried first, in BrickLink's current image layout,
/// then each padded spelling of its pattern number (see `BrickLinkItemNumber`).
/// The first one with an image in the part's color wins, and that image lands
/// in the thumbnail cache on the way, ready for the row that asked.
public actor PartImageLocator {
	public static let shared = PartImageLocator()

	private let thumbnails: ThumbnailCacheManager

	/// One lookup per number and color for the app's lifetime, found or not, so
	/// a row scrolling back into view does not ask BrickLink again.
	private var lookups: [String: Task<String?, Error>] = [:]

	public init(thumbnails: ThumbnailCacheManager = .shared) {
		self.thumbnails = thumbnails
	}

	/// The number BrickLink shows the part numbered `partID` under now: that
	/// number itself when only its image moved, a padded spelling of it when
	/// BrickLink renumbered the part. `nil` when none has an image in `colorID`,
	/// or BrickLink could not be reached.
	public func currentItemNumber(for partID: String, colorID: String) async -> String? {
		let key = "\(partID)|\(colorID)"

		let lookup: Task<String?, Error>
		if let existing = lookups[key] {
			lookup = existing
		} else {
			lookup = Task { try await self.findItemNumber(for: partID, colorID: colorID) }
			lookups[key] = lookup
		}

		do {
			return try await lookup.value
		} catch {
			// A failed request says nothing about the part, so the next row
			// showing it may ask again.
			if lookups[key] == lookup {
				lookups[key] = nil
			}
			return nil
		}
	}

	private func findItemNumber(for partID: String, colorID: String) async throws -> String? {
		for candidate in [partID] + BrickLinkItemNumber.renumberingCandidates(for: partID) {
			guard let url = Part.makeColorSpecificThumbnailURL(partID: candidate, colorID: colorID) else {
				return nil
			}

			do {
				let data = try await thumbnails.data(for: url)

				// Healing rewrites the collection, so only a real image counts as
				// proof — not, say, a bot-protection page sent with a 2xx status.
				if Self.isImage(data) {
					return candidate
				}

				await thumbnails.removeCachedData(for: url)
			} catch let error as ThumbnailCacheError where error.isNotFound {
				continue
			}
		}

		return nil
	}

	private static func isImage(_ data: Data) -> Bool {
		guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
		return CGImageSourceGetType(source) != nil && CGImageSourceGetCount(source) > 0
	}
}

/// Repairs stored parts whose thumbnail BrickLink no longer serves.
///
/// BrickLink renumbers printed parts from time to time (`14769pb328` is now
/// `14769pb0328`), and the old number's images, catalog page and search results
/// all vanish with it. A thumbnail that answers "not found" is the first sign,
/// so that is where healing starts.
public enum PartImageHealing {
	/// Finds where `part`'s image lives now and moves every part and order line
	/// with its number there.
	///
	/// - Returns: The part's thumbnail URL after healing, or `nil` when BrickLink
	///   has no image for it under any spelling of its number.
	@MainActor
	public static func healThumbnail(
		of part: Part,
		in modelContext: ModelContext,
		locator: PartImageLocator = .shared
	) async -> URL? {
		await healThumbnail(partID: part.partID, colorID: part.colorID, in: modelContext, locator: locator)
	}

	/// The order-line counterpart of `healThumbnail(of:in:locator:)`.
	@MainActor
	public static func healThumbnail(
		of orderPart: OrderPart,
		in modelContext: ModelContext,
		locator: PartImageLocator = .shared
	) async -> URL? {
		guard orderPart.itemType == .part else { return nil }
		return await healThumbnail(partID: orderPart.partID, colorID: orderPart.colorID, in: modelContext, locator: locator)
	}

	/// Moves every part and order line numbered `oldNumber` to `newNumber`, in
	/// every color — BrickLink renumbers the item, not one color of it — with the
	/// image URLs of the new number.
	@MainActor
	@discardableResult
	static func moveParts(numbered oldNumber: String, to newNumber: String, in modelContext: ModelContext) throws -> Int {
		let parts = try modelContext.fetch(FetchDescriptor<Part>(
			predicate: #Predicate { $0.partID == oldNumber }
		))

		let partType = OrderPart.ItemType.part.rawValue
		let orderParts = try modelContext.fetch(FetchDescriptor<OrderPart>(
			predicate: #Predicate { $0.partID == oldNumber && $0.itemTypeRawValue == partType }
		))

		for part in parts {
			part.adoptItemNumber(newNumber)
		}

		for orderPart in orderParts {
			orderPart.adoptItemNumber(newNumber)
		}

		let movedCount = parts.count + orderParts.count
		if movedCount > 0 {
			try modelContext.save()
		}

		return movedCount
	}

	// The model is read before the lookup and never after it: the part may be
	// deleted while BrickLink answers, say by a set refresh.
	@MainActor
	private static func healThumbnail(
		partID: String,
		colorID: String,
		in modelContext: ModelContext,
		locator: PartImageLocator
	) async -> URL? {
		guard let itemNumber = await locator.currentItemNumber(for: partID, colorID: colorID) else {
			return nil
		}

		// The image is there whether or not the move saves, so show it either way.
		_ = try? moveParts(numbered: partID, to: itemNumber, in: modelContext)

		return Part.makeColorSpecificThumbnailURL(partID: itemNumber, colorID: colorID)
	}
}
