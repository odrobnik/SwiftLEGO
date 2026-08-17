import Foundation

/// Reads set and minifigure inventories from BrickLink.
///
/// The legacy `catalogItemInv.asp` endpoint is behind a JavaScript challenge and
/// answers scripted requests with a WAF interstitial, so inventories come from
/// the pair of pages BrickLink's own catalog view uses:
///
/// 1. `catalogitem.page` resolves an item number to BrickLink's internal
///    numeric id, and carries the display name, thumbnail and categories.
/// 2. `catalogitem_invtab.page`, keyed by that id, returns the inventory table.
public final class BrickLinkInventoryService {
	public enum InventoryError: Error {
		case partsTableNotFound
	}

	/// Guards against an item whose inventory transitively contains itself.
	private static let maximumInventoryDepth = 4

	public init() {}

	public func fetchInventory(for setNumber: String) async throws -> BrickLinkInventory {
		let page = try await catalogItemPage(type: .set, number: setNumber)
		let table = try await inventoryTable(idItem: page.idItem, itemNumber: setNumber)

		guard !table.parts.isEmpty || !table.minifigures.isEmpty else {
			throw InventoryError.partsTableNotFound
		}

		async let parts = enrichedParts(from: table.parts, depth: 0)
		async let minifigures = enrichedMinifigures(from: table.minifigures)

		let resolvedName = sanitizeSetName(page.name)

		return BrickLinkInventory(
			setNumber: setNumber,
			name: resolvedName.isEmpty ? "Set \(setNumber)" : resolvedName,
			thumbnailURL: page.thumbnailURL,
			parts: try await parts,
			categories: page.categories,
			minifigures: try await minifigures
		)
	}

	// MARK: - Fetching

	private func catalogItemPage(
		type: BrickLinkCatalogItemPage.ItemType,
		number: String
	) async throws -> BrickLinkCatalogItemPage {
		let url = BrickLinkCatalogItemPage.url(for: type, number: number)
		let data = try await HTMLFetcher.data(from: url)

		return try await BrickLinkCatalogItemPage.parse(html: data, baseURL: url)
	}

	private func inventoryTable(idItem: String, itemNumber: String) async throws -> BrickLinkInventoryTable {
		let url = BrickLinkInventoryTable.url(idItem: idItem, itemNumber: itemNumber)
		let data = try await HTMLFetcher.data(from: url)

		return try await BrickLinkInventoryTable.parse(html: data, baseURL: url)
	}

	// MARK: - Parts

	private func enrichedParts(
		from rows: [BrickLinkInventoryTable.ItemRow],
		depth: Int
	) async throws -> [BrickLinkPart] {
		guard !rows.isEmpty else { return [] }

		return try await withThrowingTaskGroup(of: (Int, BrickLinkPart).self) { group in
			for (index, row) in rows.enumerated() {
				group.addTask {
					(index, try await self.part(from: row, depth: depth))
				}
			}

			var ordered: [BrickLinkPart?] = Array(repeating: nil, count: rows.count)
			for try await (index, part) in group {
				ordered[index] = part
			}

			return ordered.compactMap { $0 }
		}
	}

	private func part(from row: BrickLinkInventoryTable.ItemRow, depth: Int) async throws -> BrickLinkPart {
		var subparts: [BrickLinkPart] = []
		var inventoryURL: URL?

		if row.hasOwnInventory,
		   let idItem = row.idItem,
		   depth < Self.maximumInventoryDepth {
			inventoryURL = BrickLinkInventoryTable.url(idItem: idItem, itemNumber: row.itemNumber)

			// A missing sub-inventory should not fail the whole import.
			if let table = try? await inventoryTable(idItem: idItem, itemNumber: row.itemNumber) {
				subparts = try await enrichedParts(from: table.parts, depth: depth + 1)
			}
		}

		return makePart(from: row, inventoryURL: inventoryURL, subparts: subparts)
	}

	private func makePart(
		from row: BrickLinkInventoryTable.ItemRow,
		inventoryURL: URL?,
		subparts: [BrickLinkPart]
	) -> BrickLinkPart {
		let name = row.name.isEmpty ? row.description : row.name

		return BrickLinkPart(
			partID: row.itemNumber,
			partURL: row.itemURL,
			name: name,
			colorName: Self.colorName(description: row.description, name: row.name),
			colorID: row.colorID,
			imageURL: row.imageURL,
			fullImageURL: Self.fullSizeImageURL(from: row.imageURL),
			quantity: row.quantity,
			section: row.section,
			inventoryURL: inventoryURL,
			subparts: subparts
		)
	}

	// MARK: - Minifigures

	private func enrichedMinifigures(
		from rows: [BrickLinkInventoryTable.ItemRow]
	) async throws -> [BrickLinkMinifigure] {
		guard !rows.isEmpty else { return [] }

		return try await withThrowingTaskGroup(of: (Int, BrickLinkMinifigure).self) { group in
			for (index, row) in rows.enumerated() {
				group.addTask {
					(index, try await self.minifigure(from: row))
				}
			}

			var ordered: [BrickLinkMinifigure?] = Array(repeating: nil, count: rows.count)
			for try await (index, minifigure) in group {
				ordered[index] = minifigure
			}

			return ordered.compactMap { $0 }
		}
	}

	private func minifigure(from row: BrickLinkInventoryTable.ItemRow) async throws -> BrickLinkMinifigure {
		// The minifigure's own catalog page carries its category breadcrumb by
		// name; the inventory row only has the numeric category path.
		let page = try? await catalogItemPage(type: .minifigure, number: row.itemNumber)
		let idItem = page?.idItem ?? row.idItem

		var parts: [BrickLinkPart] = []
		var inventoryURL: URL?

		if let idItem {
			inventoryURL = BrickLinkInventoryTable.url(idItem: idItem, itemNumber: row.itemNumber)

			if let table = try? await inventoryTable(idItem: idItem, itemNumber: row.itemNumber) {
				parts = try await enrichedParts(from: table.parts, depth: 1)

				// A minifigure inventory can itself list minifigures; the old
				// scraper folded those in as parts, so keep doing that.
				parts += table.minifigures.map { nested in
					BrickLinkPart(
						partID: nested.itemNumber,
						partURL: nested.itemURL,
						name: nested.name.isEmpty ? nested.itemNumber : nested.name,
						colorName: "Minifigure",
						colorID: "0",
						imageURL: nested.imageURL,
						fullImageURL: Self.fullSizeImageURL(from: nested.imageURL),
						quantity: nested.quantity,
						section: .regular,
						inventoryURL: nested.idItem.map {
							BrickLinkInventoryTable.url(idItem: $0, itemNumber: nested.itemNumber)
						}
					)
				}
			}
		}

		let resolvedName = page?.name.isEmpty == false ? page!.name : row.name

		return BrickLinkMinifigure(
			identifier: row.itemNumber,
			name: resolvedName.isEmpty ? row.itemNumber : resolvedName,
			quantity: row.quantity,
			imageURL: Self.fullSizeImageURL(from: row.imageURL) ?? row.imageURL,
			catalogURL: BrickLinkCatalogItemPage.url(for: .minifigure, number: row.itemNumber),
			inventoryURL: inventoryURL,
			categories: page?.categories ?? [],
			parts: parts
		)
	}

	// MARK: - Helpers

	/// The bold description is the color name followed by the item name, and the
	/// image `alt` is that item name on its own.
	static func colorName(description: String, name: String) -> String {
		let description = description.collapsedWhitespace()
		guard !name.isEmpty else { return description }

		let colorName: String
		if description.hasSuffix(name) {
			colorName = String(description.dropLast(name.count))
				.trimmingCharacters(in: .whitespacesAndNewlines)
		} else if let range = description.range(of: name) {
			colorName = String(description[..<range.lowerBound])
				.trimmingCharacters(in: .whitespacesAndNewlines)
		} else {
			return description
		}

		return isPlaceholderColorName(colorName) ? "" : colorName
	}

	/// Subparts of a multipack are listed as "(Variable Color)" because the color
	/// depends on the pack. Reporting no color lets the importer inherit the
	/// parent part's color instead of showing the placeholder to the user.
	private static func isPlaceholderColorName(_ colorName: String) -> Bool {
		colorName.hasPrefix("(") && colorName.hasSuffix(")")
	}

	/// BrickLink thumbnails live under a two-letter code ending in `T` with a
	/// `.t1` filename suffix; the full-size image swaps both.
	/// `/ItemImage/PT/11/32828.t1.png` → `/ItemImage/PN/11/32828.png`
	static func fullSizeImageURL(from thumbnail: URL?) -> URL? {
		guard let thumbnail,
			  var components = URLComponents(url: thumbnail, resolvingAgainstBaseURL: false) else {
			return nil
		}

		var segments = components.path.split(separator: "/").map(String.init)

		guard let imageIndex = segments.firstIndex(of: "ItemImage"),
			  segments.index(after: imageIndex) < segments.endIndex else {
			return nil
		}

		let code = segments[imageIndex + 1]
		if code.count == 2, code.hasSuffix("T") {
			segments[imageIndex + 1] = code.dropLast() + "N"
		}

		if let filename = segments.last {
			segments[segments.count - 1] = filename.replacingOccurrences(of: ".t1.", with: ".")
		}

		components.path = "/" + segments.joined(separator: "/")

		return components.url
	}
}

private extension BrickLinkInventoryService {
	/// Drops a `{Word}` qualifier that merely repeats the word before it.
	func sanitizeSetName(_ raw: String) -> String {
		guard let regex = try? NSRegularExpression(pattern: #"\{\s*([^}]+)\s*\}"#) else { return raw }

		var result = raw
		let fullRange = NSRange(result.startIndex..<result.endIndex, in: result)

		for match in regex.matches(in: result, range: fullRange).reversed() {
			guard let braceRange = Range(match.range, in: result),
				  let contentRange = Range(match.range(at: 1), in: result) else {
				continue
			}

			let braceWord = result[contentRange].trimmingCharacters(in: .whitespacesAndNewlines)
			guard !braceWord.isEmpty else {
				result.removeSubrange(braceRange)
				continue
			}

			guard let wordRange = precedingWordRange(before: braceRange.lowerBound, in: result) else {
				continue
			}

			let precedingWord = result[wordRange].trimmingCharacters(in: .whitespacesAndNewlines)
			guard normalizedToken(precedingWord) == normalizedToken(braceWord) else { continue }

			var whitespaceStart = braceRange.lowerBound
			var cursor = braceRange.lowerBound
			while cursor > result.startIndex {
				let prior = result.index(before: cursor)
				if result[prior].isWhitespace {
					cursor = prior
				} else {
					whitespaceStart = result.index(after: prior)
					break
				}
			}

			result.removeSubrange(whitespaceStart..<braceRange.upperBound)
		}

		return result
			.replacingOccurrences(of: "  ", with: " ")
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	func precedingWordRange(before boundary: String.Index, in text: String) -> Range<String.Index>? {
		var cursor = boundary

		while cursor > text.startIndex {
			let prior = text.index(before: cursor)
			if text[prior].isWhitespace {
				cursor = prior
			} else {
				break
			}
		}

		let wordEnd = cursor
		var wordStart = cursor
		var found = false

		while wordStart > text.startIndex {
			let prior = text.index(before: wordStart)
			let character = text[prior]
			if character.isLetter || character.isNumber || character == "'" || character == "’" {
				wordStart = prior
				found = true
			} else {
				break
			}
		}

		guard found, wordStart < wordEnd else { return nil }

		return wordStart..<wordEnd
	}

	func normalizedToken(_ text: String) -> String {
		text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
	}
}
