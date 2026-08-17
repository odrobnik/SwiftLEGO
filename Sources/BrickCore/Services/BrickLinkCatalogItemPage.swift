import Foundation
import SwiftTextHTML

/// The metadata BrickLink's `catalogitem.page` carries for a single catalog item.
///
/// The legacy `catalogItemInv.asp` endpoint now sits behind a JavaScript
/// challenge, so inventories are read from `catalogitem_invtab.page` instead.
/// That endpoint is keyed by BrickLink's internal numeric item id, which this
/// page supplies alongside the display name, thumbnail and category breadcrumb.
struct BrickLinkCatalogItemPage: Equatable {
	enum ItemType: String {
		case set = "S"
		case minifigure = "M"
	}

	let idItem: String
	let name: String
	let thumbnailURL: URL?
	let categories: [BrickLinkCategory]

	enum ParseError: LocalizedError {
		case missingIdItem(URL)

		var errorDescription: String? {
			switch self {
				case .missingIdItem(let url):
					return "\(url.absoluteString) did not contain a BrickLink item id."
			}
		}
	}

	static func url(for type: ItemType, number: String) -> URL {
		var components = URLComponents()
		components.scheme = "https"
		components.host = "www.bricklink.com"
		components.path = "/v2/catalog/catalogitem.page"
		components.queryItems = [URLQueryItem(name: type.rawValue, value: number)]

		return components.url!
	}

	static func parse(html: Data, baseURL: URL) async throws -> BrickLinkCatalogItemPage {
		let markup = String(decoding: html, as: UTF8.self)

		guard let idItem = firstCapture(of: #"idItem\s*:\s*(\d+)"#, in: markup) else {
			throw ParseError.missingIdItem(baseURL)
		}

		let domBuilder = try await DomBuilder(html: html, baseURL: baseURL)
		let root = domBuilder.root

		return BrickLinkCatalogItemPage(
			idItem: idItem,
			name: root.flatMap(displayName(in:)) ?? "",
			thumbnailURL: thumbnailURL(in: markup),
			categories: root.map(categories(in:)) ?? []
		)
	}

	// MARK: - Pieces

	/// `<h1 id="item-name-title">The Magical Madrigal House</h1>`
	private static func displayName(in root: DOMElement) -> String? {
		guard let heading = root.firstDescendant(where: { $0.attribute("id") == "item-name-title" }) else {
			return nil
		}

		let name = heading.collapsedText()
		return name.isEmpty ? nil : name
	}

	/// The page's `_var_item` script block holds the catalog imagery.
	private static func thumbnailURL(in markup: String) -> URL? {
		let keys = ["strLegacyLargeImgUrl", "strMainLImgUrl", "strMainSImgUrl"]

		for key in keys {
			guard let raw = firstCapture(of: "\(key)\\s*:\\s*'([^']+)'", in: markup) else { continue }
			if let url = absoluteURL(from: raw) { return url }
		}

		return nil
	}

	/// The breadcrumb reads `Catalog: Sets: Disney: Encanto: 43245-1`. The leading
	/// "Catalog" link and the trailing item number are not categories.
	private static func categories(in root: DOMElement) -> [BrickLinkCategory] {
		var categories: [BrickLinkCategory] = []

		for anchor in root.descendantElements(named: "a") {
			guard let href = anchor.attribute("href") else { continue }

			let name = anchor.collapsedText()
			guard !name.isEmpty else { continue }

			if href.contains("catalogTree.asp?itemType=") {
				// The item-type root of the breadcrumb: "Sets", "Minifigures", "Parts".
				categories.append(BrickLinkCategory(id: nil, name: name))
				continue
			}

			guard href.contains("catalogList.asp"), let id = catString(from: href) else { continue }

			categories.append(BrickLinkCategory(id: id, name: name))
		}

		return categories
	}

	private static func catString(from href: String) -> String? {
		guard let components = URLComponents(string: href.replacingOccurrences(of: "&amp;", with: "&")) else {
			return nil
		}

		return components.queryItems?.first(where: { item in
			let name = item.name.lowercased()
			return name == "catstring" || name == "catid"
		})?.value
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

	private static func firstCapture(of pattern: String, in text: String) -> String? {
		guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

		let range = NSRange(text.startIndex..<text.endIndex, in: text)
		guard let match = regex.firstMatch(in: text, range: range),
			  let captured = Range(match.range(at: 1), in: text) else {
			return nil
		}

		return String(text[captured])
	}
}
