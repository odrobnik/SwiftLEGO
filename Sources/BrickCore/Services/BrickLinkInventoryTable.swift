import Foundation
import SwiftTextHTML

/// Parses BrickLink's `catalogitem_invtab.page`, the inventory table its own
/// catalog page loads.
///
/// The markup labels every row with a class, so sections and item types are read
/// from those rather than inferred from text: `pciinvExtraHeader` carries
/// "Regular Items:" / "Extra Items:" / "Counterparts:", `pciinvItemTypeHeader`
/// carries "Parts:" / "Minifigures:", and `pciinvItemRow` rows are the items.
/// The trailing summary table repeats the section labels under
/// `pciinvSummary…` classes, which are ignored.
struct BrickLinkInventoryTable: Equatable {
	/// One inventory line, straight off the page and not yet interpreted.
	struct ItemRow: Equatable {
		/// BrickLink's internal numeric id, used to fetch this item's own inventory.
		let idItem: String?
		let itemNumber: String
		/// The image `alt`, which is the item name without any color prefix.
		let name: String
		/// The bold description, which is the color name followed by the item name.
		let description: String
		let colorID: String
		let quantity: Int
		let imageURL: URL?
		let itemURL: URL?
		/// True when the row carries an "(inv)" link, i.e. the item has subparts.
		let hasOwnInventory: Bool
		let section: BrickLinkPartSection
	}

	let parts: [ItemRow]
	let minifigures: [ItemRow]

	private enum ItemType {
		case parts
		case minifigures
		case other
	}

	static func url(idItem: String, itemNumber: String) -> URL {
		var components = URLComponents()
		components.scheme = "https"
		components.host = "www.bricklink.com"
		components.path = "/v2/catalog/catalogitem_invtab.page"
		components.queryItems = [
			URLQueryItem(name: "idItem", value: idItem),
			URLQueryItem(name: "itemNoSeq", value: itemNumber)
		]

		return components.url!
	}

	static func parse(html: Data, baseURL: URL) async throws -> BrickLinkInventoryTable {
		let domBuilder = try await DomBuilder(html: html, baseURL: baseURL)

		guard let root = domBuilder.root else {
			return BrickLinkInventoryTable(parts: [], minifigures: [])
		}

		var parts: [ItemRow] = []
		var minifigures: [ItemRow] = []
		var section: BrickLinkPartSection = .regular
		var itemType: ItemType = .parts

		for row in root.descendantElements(named: "tr") {
			if row.hasClass("pciinvExtraHeader") {
				if let detected = self.section(from: row.collapsedText()) {
					section = detected
				}
				continue
			}

			if row.hasClass("pciinvItemTypeHeader") {
				itemType = self.itemType(from: row.collapsedText())
				continue
			}

			guard row.hasClass("pciinvItemRow"),
				  let item = itemRow(from: row, section: section, baseURL: baseURL) else {
				continue
			}

			switch itemType {
				case .parts:
					parts.append(item)

				case .minifigures:
					minifigures.append(item)

				case .other:
					continue
			}
		}

		return BrickLinkInventoryTable(parts: parts, minifigures: minifigures)
	}

	// MARK: - Rows

	private static func itemRow(
		from row: DOMElement,
		section: BrickLinkPartSection,
		baseURL: URL
	) -> ItemRow? {
		let cells = row.childElements.filter { $0.name == "td" }
		guard cells.count >= 5 else { return nil }

		let image = cells[1].descendantElements(named: "img").first
		let anchors = cells[3].descendantElements(named: "a")

		guard let itemAnchor = anchors.first else { return nil }

		let itemNumber = itemAnchor.collapsedText()
		guard !itemNumber.isEmpty else { return nil }

		let quantity = Int(
			cells[2].collapsedText().replacingOccurrences(of: ",", with: "")
		) ?? 0

		let description = cells[4]
			.firstDescendant(where: { $0.name == "b" })?
			.collapsedText() ?? ""

		let colorID = row.firstAttributeValue("data-colorid")?
			.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

		return ItemRow(
			idItem: row.firstAttributeValue("data-itemid"),
			itemNumber: itemNumber,
			name: image?.attribute("alt")?.collapsedWhitespace() ?? "",
			description: description,
			colorID: colorID == "0" ? "" : colorID,
			quantity: quantity,
			imageURL: image?.attribute("src").flatMap { absoluteURL(from: $0) },
			itemURL: itemAnchor.attribute("href").flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL },
			hasOwnInventory: anchors.count > 1,
			section: section
		)
	}

	private static func section(from text: String) -> BrickLinkPartSection? {
		let normalized = text
			.replacingOccurrences(of: ":", with: "")
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.lowercased()

		switch normalized {
			case "regular", "regular items", "regular item":
				return .regular

			case "extra", "extras", "extra items", "extra item":
				return .extra

			case "counterpart", "counterparts", "counterpart items", "counterparts items":
				return .counterpart

			case "alternate", "alternates", "alternate items":
				return .alternate

			default:
				return nil
		}
	}

	private static func itemType(from text: String) -> ItemType {
		let normalized = text.lowercased()

		if normalized.hasPrefix("minifigure") { return .minifigures }
		if normalized.hasPrefix("part") { return .parts }

		return .other
	}

	private static func absoluteURL(from raw: String) -> URL? {
		if raw.hasPrefix("//") {
			return URL(string: "https:\(raw)")
		}

		if raw.hasPrefix("/") {
			return URL(string: "https://www.bricklink.com\(raw)")
		}

		return URL(string: raw)
	}
}

extension String {
	func collapsedWhitespace() -> String {
		replacingOccurrences(of: "\u{00a0}", with: " ")
			.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}
