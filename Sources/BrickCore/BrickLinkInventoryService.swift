import Foundation

public final class BrickLinkInventoryService {
	private struct ParsedInventory {
		let name: String?
		let thumbnailURL: URL?
		let categories: [BrickLinkCategory]
		let parts: [BrickLinkPart]
		let minifigures: [ParsedMinifigure]
	}

	private struct ParsedMinifigure {
		let identifier: String
		let name: String
		let quantity: Int
		let imageURL: URL?
		let catalogURL: URL?
		let inventoryURL: URL?
		let categories: [BrickLinkCategory]
	}

	public enum InventoryError: Error {
		case invalidResponse
		case partsTableNotFound
		case malformedRow(String)
		case missingSetName
	}

	public init() {}

	public func fetchInventory(for setNumber: String) async throws -> BrickLinkInventory {
		let url = inventoryURL(for: setNumber)
		let converter = HTML💡Markdown(url: url)
		let markdown = try await converter.markdown()
		print("=== BrickLink Inventory Markdown: \(setNumber) ===")
		print(markdown)
		print("=== End Markdown ===")

		let parsed = try parse(markdown: markdown, setNumber: setNumber, baseURL: url)
		let minifigures = try await enrichMinifigures(parsed.minifigures)

		return BrickLinkInventory(
			setNumber: setNumber,
			name: parsed.name ?? "Set \(setNumber)",
			thumbnailURL: parsed.thumbnailURL,
			parts: parsed.parts,
			categories: parsed.categories,
			minifigures: minifigures
		)
	}

	// MARK: - Parsing

	private func parse(markdown: String, setNumber: String, baseURL: URL) throws -> ParsedInventory {
		let lines = markdown.components(separatedBy: .newlines)

		guard let tableHeaderIndex = lines.firstIndex(where: { $0.contains("| **Image**") }) else {
			throw InventoryError.partsTableNotFound
		}

		let metadata = parseMetadata(from: lines, baseURL: baseURL)

		let (parts, minifigures) = try parseInventoryItems(
			lines: lines,
			startIndex: tableHeaderIndex + 2,
			baseURL: baseURL,
			allowMinifigures: true
		)

		return ParsedInventory(
			name: metadata.name,
			thumbnailURL: metadata.thumbnailURL,
			categories: metadata.categories,
			parts: parts,
			minifigures: minifigures
		)
	}

	private enum InventoryItemType {
		case parts
		case minifigures
	}

	private func parseInventoryItems(
		lines: [String],
		startIndex: Int,
		baseURL: URL,
		allowMinifigures: Bool
	) throws -> ([BrickLinkPart], [ParsedMinifigure]) {
		var parts: [BrickLinkPart] = []
		var minifigures: [ParsedMinifigure] = []
		var index = startIndex
		var currentSection: BrickLinkPartSection = .regular
		var currentItemType: InventoryItemType = .parts

		while index < lines.count {
			let line = lines[index].trimmingCharacters(in: .whitespaces)
			if line.isEmpty {
				index += 1
				continue
			}

			if !line.hasPrefix("|") {
				index += 1
				continue
			}

			if let detectedSection = detectSection(from: line) {
				currentSection = detectedSection
				index += 1
				continue
			}

			if allowMinifigures, let detectedItemType = detectItemType(from: line) {
				currentItemType = detectedItemType
				index += 1
				continue
			}

			var columns = line
				.split(separator: "|", omittingEmptySubsequences: false)
				.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

			while let first = columns.first, first.isEmpty {
				columns.removeFirst()
			}

			while let last = columns.last, last.isEmpty {
				columns.removeLast()
			}

			do {
				switch currentItemType {
				case .parts:
					guard columns.contains(where: { $0.contains("catalog/catalogitem.page?P=") }) else {
						index += 1
						continue
					}
					let part = try parsePartRow(columns: columns, baseURL: baseURL, section: currentSection)
					parts.append(part)
				case .minifigures:
					guard columns.contains(where: { $0.contains("catalogitem.page?M=") }) else {
						index += 1
						continue
					}
					let minifigure = try parseMinifigureRow(columns: columns, baseURL: baseURL)
					minifigures.append(minifigure)
				}
			} catch {
				throw InventoryError.malformedRow(line)
			}

			index += 1
		}

		return (parts, minifigures)
	}

	private func enrichMinifigures(_ minifigures: [ParsedMinifigure]) async throws -> [BrickLinkMinifigure] {
		guard !minifigures.isEmpty else { return [] }

		return try await withThrowingTaskGroup(of: (Int, BrickLinkMinifigure).self) { group in
			for (index, minifigure) in minifigures.enumerated() {
				group.addTask {
					let parts = try await self.fetchMinifigureParts(for: minifigure)
					return (
						index,
						BrickLinkMinifigure(
							identifier: minifigure.identifier,
							name: minifigure.name,
							quantity: minifigure.quantity,
							imageURL: minifigure.imageURL,
							catalogURL: minifigure.catalogURL,
							inventoryURL: minifigure.inventoryURL,
							categories: minifigure.categories,
							parts: parts
						)
					)
				}
			}

			var ordered: [BrickLinkMinifigure?] = Array(repeating: nil, count: minifigures.count)
			for try await (index, minifigure) in group {
				ordered[index] = minifigure
			}

			return ordered.compactMap { $0 }
		}
	}

	private func fetchMinifigureParts(for minifigure: ParsedMinifigure) async throws -> [BrickLinkPart] {
		let url = minifigure.inventoryURL ?? inventoryURL(forMinifigure: minifigure.identifier)
		let converter = HTML💡Markdown(url: url)
		let markdown = try await converter.markdown()

		let lines = markdown.components(separatedBy: .newlines)
		guard let tableHeaderIndex = lines.firstIndex(where: { $0.contains("| **Image**") }) else {
			throw InventoryError.partsTableNotFound
		}

		let (parts, _) = try parseInventoryItems(
			lines: lines,
			startIndex: tableHeaderIndex + 2,
			baseURL: url,
			allowMinifigures: false
		)

		return parts
	}

	private func detectSection(from line: String) -> BrickLinkPartSection? {
		let sanitizedColumns = line
			.replacingOccurrences(of: "**", with: "")
			.split(separator: "|", omittingEmptySubsequences: false)
			.map {
				$0
						.trimmingCharacters(in: .whitespacesAndNewlines)
						.lowercased()
				}
				.filter { !$0.isEmpty }

			for column in sanitizedColumns {
				let normalized = column
					.replacingOccurrences(of: ":", with: "")
					.replacingOccurrences(of: ".", with: "")
					.trimmingCharacters(in: .whitespacesAndNewlines)

				switch normalized {
				case "regular", "regular items", "regular item":
					return .regular
				case "extra", "extras", "extra items", "extra item":
					return .extra
				case "counterpart", "counterparts", "counterpart items", "counterparts items":
					return .counterpart
				case "alternate", "alternate items", "alternates":
					return .alternate
				default:
					continue
				}
			}

			return nil
		}

	private func parsePartRow(
		columns: [String],
		baseURL: URL,
		section: BrickLinkPartSection
	) throws -> BrickLinkPart {
		let imageColumn = columns.first(where: { $0.contains("catalogItemPic.asp") })
		let partLinkColumn = columns.first(where: { $0.contains("catalog/catalogitem.page?P=") })
		let descriptionColumn = columns.first(where: { $0.contains("**") && !$0.contains("Part No:") })

		let imageURL = extractImageURL(from: imageColumn)

		let quantity = columns
			.compactMap { Int($0) }
			.first ?? 0

		let partName = normalizeWhitespace(extractPartName(from: imageColumn))

		let (partID, partURL) = extractLink(from: partLinkColumn, baseURL: baseURL)

		let rawDescription = descriptionColumn?
			.replacingOccurrences(of: "**", with: "")
			.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		let normalizedDescription = normalizeWhitespace(rawDescription)

		var colorName = ""
		if !partName.isEmpty, let range = normalizedDescription.range(of: partName) {
			colorName = String(normalizedDescription[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
		}

		if colorName.isEmpty {
			colorName = normalizedDescription
		}

		let colorID = partURL.flatMap { url in
			URLComponents(url: url, resolvingAgainstBaseURL: false)?
				.queryItems?
				.first(where: { $0.name.lowercased() == "idcolor" })?
				.value
		} ?? ""

		return BrickLinkPart(
			partID: partID,
			partURL: partURL,
			name: partName.isEmpty ? normalizedDescription : partName,
			colorName: colorName,
			colorID: colorID,
			imageURL: imageURL,
			quantity: quantity,
			section: section
		)
	}

	private func parseMinifigureRow(
		columns: [String],
		baseURL: URL
	) throws -> ParsedMinifigure {
		let imageColumn = columns.first(where: { $0.contains("catalogItemPic.asp?M=") })
		let minifigLinkColumn = columns.first(where: { $0.contains("catalogitem.page?M=") })
		let descriptionColumn = columns.first(where: { $0.contains("Catalog") })

		let imageURL = extractImageURL(from: imageColumn)
		let quantity = columns
			.compactMap { Int($0) }
			.first ?? 0

		let rawName = normalizeWhitespace(extractPartName(from: imageColumn))
		let (identifier, catalogURL) = extractLink(from: minifigLinkColumn, baseURL: baseURL)
		guard !identifier.isEmpty else {
			throw InventoryError.malformedRow(columns.joined(separator: "|"))
		}
		let inventoryURL = extractInventoryURL(from: minifigLinkColumn, baseURL: baseURL)

		var categories: [BrickLinkCategory] = []
		if let descriptionColumn {
			categories = extractCategories(from: descriptionColumn, baseURL: baseURL)
		}

		var resolvedName = rawName
		if resolvedName.isEmpty, let descriptionColumn {
			let sanitized = descriptionColumn
				.replacingOccurrences(of: "**", with: "")
				.replacingOccurrences(of: "[Catalog]", with: "")
			let components = sanitized.split(separator: "\n")
			if let first = components.first {
				resolvedName = normalizeWhitespace(String(first))
			}
		}

		return ParsedMinifigure(
			identifier: identifier,
			name: resolvedName,
			quantity: quantity,
			imageURL: imageURL,
			catalogURL: catalogURL,
			inventoryURL: inventoryURL,
			categories: categories
		)
	}

	private func extractImageURL(from column: String?) -> URL? {
		guard let column else { return nil }
		let nsRange = NSRange(column.startIndex..<column.endIndex, in: column)
		guard let match = imageRegex.firstMatch(in: column, options: [], range: nsRange) else {
			return nil
		}

		guard let range = Range(match.range(at: 1), in: column) else {
			return nil
		}

		let urlString = String(column[range])

		if let url = URL(string: urlString), url.scheme != nil {
			return url
		}

		// Fallback: construct absolute URL relative to BrickLink
		return URL(string: "https://www.bricklink.com\(urlString)")
	}

	private func extractPartName(from column: String?) -> String {
		guard let column, let nameRange = column.range(of: "Name:") else {
			return ""
		}

		let nameStart = column.index(nameRange.upperBound, offsetBy: 0)
		let remainder = column[nameStart...]
		guard let endRange = remainder.range(of: "](") else {
			return ""
		}

		let name = remainder[..<endRange.lowerBound]
		return name.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private func extractLink(from column: String?, baseURL: URL) -> (String, URL?) {
		guard let column else { return ("", nil) }

		let nsRange = NSRange(column.startIndex..<column.endIndex, in: column)
		guard let match = linkRegex.firstMatch(in: column, options: [], range: nsRange) else {
			return (column, nil)
		}

		guard
			let textRange = Range(match.range(at: 1), in: column),
			let urlRange = Range(match.range(at: 2), in: column)
		else {
			return (column, nil)
		}

		let text = String(column[textRange])
		let urlString = String(column[urlRange])
		let url = URL(string: urlString, relativeTo: baseURL)
		return (text, url?.absoluteURL)
	}

	private func extractInventoryURL(from column: String?, baseURL: URL) -> URL? {
		guard let column else { return nil }
		let nsRange = NSRange(column.startIndex..<column.endIndex, in: column)
		let matches = linkRegex.matches(in: column, options: [], range: nsRange)
		guard matches.count >= 2 else { return nil }

		let inventoryMatch = matches[1]
		guard let urlRange = Range(inventoryMatch.range(at: 2), in: column) else {
			return nil
		}

		let urlString = String(column[urlRange])
		return URL(string: urlString, relativeTo: baseURL)?.absoluteURL
	}

	private func extractCategories(from line: String, baseURL: URL) -> [BrickLinkCategory] {
		let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
		let matches = linkRegex.matches(in: line, options: [], range: nsRange)

		var categories: [BrickLinkCategory] = []

		for match in matches {
			guard
				let textRange = Range(match.range(at: 1), in: line),
				let urlRange = Range(match.range(at: 2), in: line)
			else {
				continue
			}

			let text = normalizeWhitespace(String(line[textRange]))
			let rawURLString = String(line[urlRange])
			guard let url = URL(string: rawURLString, relativeTo: baseURL)?.absoluteURL else {
				continue
			}

			let lowercasedURL = url.absoluteString.lowercased()

			if lowercasedURL.contains("catalogitem.page?s=") {
				break
			}

			if lowercasedURL.contains("catalogiteminv.asp?s=") {
				break
			}

			if text.caseInsensitiveCompare("Catalog") == .orderedSame {
				continue
			}

			let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
				.queryItems?
				.first(where: { item in
					let name = item.name.lowercased()
					return name == "catstring" || name == "catid"
				})?
				.value

			categories.append(BrickLinkCategory(id: id, name: text))
		}

		return categories
	}

	private func extractSetName(from line: String) -> String? {
		guard line.contains("catalogItemPic.asp?S=") else { return nil }

		let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)

		if let match = setNameRegex.firstMatch(in: line, options: [], range: nsRange),
		   let range = Range(match.range(at: 1), in: line) {
			return normalizeWhitespace(String(line[range]))
		}

		if let match = boldRegex.firstMatch(in: line, options: [], range: nsRange),
		   let range = Range(match.range(at: 1), in: line) {
			let candidate = normalizeWhitespace(String(line[range]))
			let disallowed = ["image", "qty", "parts", "regular items", "mid"]
			if disallowed.allSatisfy({ !candidate.lowercased().contains($0) }) {
				return candidate
			}
		}

		return nil
	}

	private func detectItemType(from line: String) -> InventoryItemType? {
		let lowercased = line.lowercased()
		let isMetadataRow = lowercased.contains("[catalog]")
		guard !isMetadataRow else { return nil }

		if lowercased.contains("minifigures:") {
			return .minifigures
		}

		if lowercased.contains("parts:") {
			return .parts
		}

		return nil
	}

	private func parseMetadata(
		from lines: [String],
		baseURL: URL
	) -> (name: String?, thumbnailURL: URL?, categories: [BrickLinkCategory]) {
		var name: String?
		var thumbnailURL: URL?
		var categories: [BrickLinkCategory] = []

		for line in lines {
			if name == nil, let extracted = extractSetName(from: line) {
				name = extracted
			}

			if categories.isEmpty, line.contains("[Catalog]") {
				categories = extractCategories(from: line, baseURL: baseURL)
			}

			if line.contains("catalogItemPic.asp?S="),
			   let preferred = extractImageURL(from: line),
			   preferred.absoluteString.contains("/S/") {
				thumbnailURL = promoteToHighResolution(preferred)
			} else if thumbnailURL == nil,
					  let candidate = extractImageURL(from: line) {
				thumbnailURL = promoteToHighResolution(candidate)
			}

			if name != nil, thumbnailURL != nil, !categories.isEmpty {
				break
			}
		}

		return (name, thumbnailURL, categories)
	}

	// MARK: - Helpers

	private func inventoryURL(for setNumber: String) -> URL {
		var components = URLComponents()
		components.scheme = "https"
		components.host = "www.bricklink.com"
		components.path = "/catalogItemInv.asp"
		components.queryItems = [
			URLQueryItem(name: "S", value: setNumber),
			URLQueryItem(name: "viewType", value: "R")
		]

		return components.url!
	}

	private func inventoryURL(forMinifigure identifier: String) -> URL {
		var components = URLComponents()
		components.scheme = "https"
		components.host = "www.bricklink.com"
		components.path = "/catalogItemInv.asp"
		components.queryItems = [
			URLQueryItem(name: "M", value: identifier),
			URLQueryItem(name: "viewType", value: "R")
		]

		return components.url!
	}

	private let linkRegex = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#, options: [])
	private let imageRegex = try! NSRegularExpression(pattern: #"!\[[^\]]*\]\(([^)]+)\)"#, options: [])
	private let setNameRegex = try! NSRegularExpression(pattern: #"Name:\s*([^)\]]+)"#, options: [])
	private let boldRegex = try! NSRegularExpression(pattern: #"\*\*([^*]+)\*\*"#, options: [])

}

	private extension Array where Element == String {
		subscript(safe index: Int) -> String? {
			guard indices.contains(index) else { return nil }
			return self[index]
		}
	}

private func normalizeWhitespace(_ string: String) -> String {
	string
		.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
		.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func promoteToHighResolution(_ url: URL) -> URL {
	guard let host = url.host, host.contains("bricklink.com") else {
		return url
	}

	var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
	if var path = components?.path, path.contains("/S/") {
		path = path.replacingOccurrences(of: "/S/", with: "/SL/")
		components?.path = path

		if let upgraded = components?.url {
			return upgraded
		}
	}

	return url
}
