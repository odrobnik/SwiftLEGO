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

		let parsed = try parse(markdown: markdown, setNumber: setNumber, baseURL: url)
		let enrichedParts = try await enrichParts(parsed.parts)
		let minifigures = try await enrichMinifigures(parsed.minifigures)

		return BrickLinkInventory(
			setNumber: setNumber,
			name: parsed.name ?? "Set \(setNumber)",
			thumbnailURL: parsed.thumbnailURL,
			parts: enrichedParts,
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

				var didConsumeNextLine = false

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
						let nextLine = lines[safe: index + 1]?.trimmingCharacters(in: .whitespacesAndNewlines)
						let minifigure = try parseMinifigureRow(
							columns: columns,
							nextLine: nextLine,
							baseURL: baseURL,
							consumedNextLine: &didConsumeNextLine
						)
						minifigures.append(minifigure)
					}
				} catch {
					throw InventoryError.malformedRow(line)
				}

				if didConsumeNextLine {
					index += 1
				}

				index += 1
			}

			return (parts, minifigures)
		}

	private func enrichParts(_ parts: [BrickLinkPart]) async throws -> [BrickLinkPart] {
		guard parts.contains(where: { $0.inventoryURL != nil }) else {
			return parts
		}

		return try await withThrowingTaskGroup(of: (Int, BrickLinkPart).self) { group in
			for (index, part) in parts.enumerated() where part.inventoryURL != nil {
				guard let inventoryURL = part.inventoryURL else {
					continue
				}

				group.addTask {
					let rawSubparts = try await self.fetchParts(from: inventoryURL)
					let enrichedSubparts = try await self.enrichParts(rawSubparts)

					let enrichedPart = BrickLinkPart(
						partID: part.partID,
						partURL: part.partURL,
						name: part.name,
						colorName: part.colorName,
						colorID: part.colorID,
						imageURL: part.imageURL,
						fullImageURL: part.fullImageURL,
						quantity: part.quantity,
						section: part.section,
						inventoryURL: part.inventoryURL,
						subparts: enrichedSubparts
					)

					return (index, enrichedPart)
				}
			}

			var updatedParts = parts
			for try await (index, enriched) in group {
				updatedParts[index] = enriched
			}

			return updatedParts
		}
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
							imageURL: self.preferredMinifigureImageURL(
								for: minifigure.identifier,
								fallback: minifigure.imageURL
							),
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
		return try await fetchParts(from: url, allowMinifigures: true)
	}

	private func fetchParts(from inventoryURL: URL, allowMinifigures: Bool = false) async throws -> [BrickLinkPart] {
		let converter = HTML💡Markdown(url: inventoryURL)
		let markdown = try await converter.markdown()

		let lines = markdown.components(separatedBy: .newlines)
		guard let tableHeaderIndex = lines.firstIndex(where: { $0.contains("| **Image**") }) else {
			return []
		}

		do {
			let (parts, minifigures) = try parseInventoryItems(
				lines: lines,
				startIndex: tableHeaderIndex + 2,
				baseURL: inventoryURL,
				allowMinifigures: allowMinifigures
			)

			guard allowMinifigures, !minifigures.isEmpty else { return parts }

			let minifigureParts = minifigures.map { minifigure in
				let resolvedInventoryURL = minifigure.inventoryURL ?? self.inventoryURL(forMinifigure: minifigure.identifier)
				return BrickLinkPart(
					partID: minifigure.identifier,
					partURL: minifigure.catalogURL,
					name: minifigure.name.isEmpty ? minifigure.identifier : minifigure.name,
					colorName: "Minifigure",
					colorID: "0",
					imageURL: preferredMinifigureImageURL(for: minifigure.identifier, fallback: minifigure.imageURL),
					fullImageURL: nil,
					quantity: minifigure.quantity,
					section: .regular,
					inventoryURL: resolvedInventoryURL
				)
			}

			return parts + minifigureParts
		} catch InventoryError.partsTableNotFound {
			return []
		}
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

		let imageURLs = extractImageURLs(from: imageColumn)

		let quantity = columns
			.compactMap { Int($0) }
			.first ?? 0

		let partName = normalizeWhitespace(extractPartName(from: imageColumn))

		let (partID, partURL) = extractLink(from: partLinkColumn, baseURL: baseURL)
		let inventoryURL = extractInventoryURL(from: partLinkColumn, baseURL: baseURL)

		let rawDescription = descriptionColumn?
			.replacingOccurrences(of: "**", with: "")
			.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		let normalizedDescription = normalizeWhitespace(rawDescription)
		let sanitizedDescription = sanitizeColorDescription(normalizedDescription)

		var colorName = ""
		if !partName.isEmpty, let range = sanitizedDescription.range(of: partName) {
			colorName = String(sanitizedDescription[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
		}

		if colorName.isEmpty {
			colorName = sanitizedDescription
		}

		var colorID = partURL.flatMap { url in
			URLComponents(url: url, resolvingAgainstBaseURL: false)?
				.queryItems?
				.first(where: { $0.name.lowercased() == "idcolor" })?
				.value
		} ?? ""
		colorID = colorID.trimmingCharacters(in: .whitespacesAndNewlines)
		if colorID == "0" {
			colorID = ""
		}

		let colorSpecificThumbnail = makeColorSpecificThumbnailURL(partID: partID, colorID: colorID)
		let colorSpecificFull = makeColorSpecificImageURL(partID: partID, colorID: colorID)

		let resolvedThumbnail: URL?
		if let existing = imageURLs.thumbnail,
		   !existing.path.lowercased().contains("no_image") {
			resolvedThumbnail = existing
		} else {
			resolvedThumbnail = colorSpecificThumbnail ?? imageURLs.thumbnail
		}

		let preferredFullImage = colorSpecificFull ?? imageURLs.fullsize

		return BrickLinkPart(
			partID: partID,
			partURL: partURL,
			name: partName.isEmpty ? normalizedDescription : partName,
			colorName: colorName,
			colorID: colorID,
			imageURL: resolvedThumbnail,
			fullImageURL: preferredFullImage,
			quantity: quantity,
			section: section,
			inventoryURL: inventoryURL
		)
	}

	private func parseMinifigureRow(
		columns: [String],
		nextLine: String?,
		baseURL: URL,
		consumedNextLine: inout Bool
	) throws -> ParsedMinifigure {
		let imageColumn = columns.first(where: { $0.contains("catalogItemPic.asp?M=") })
		let minifigLinkColumn = columns.first(where: { $0.contains("catalogitem.page?M=") })
		let descriptionColumn = columns.first(where: { $0.contains("Catalog") })

		let imageURL = extractImageURLs(from: imageColumn).thumbnail
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
		} else if let nextLine,
				  let categoriesColumn = categoriesColumn(from: nextLine) {
			categories = extractCategories(from: categoriesColumn, baseURL: baseURL)
			consumedNextLine = true
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

	private func extractImageURLs(from column: String?) -> (thumbnail: URL?, fullsize: URL?) {
		guard let column else { return (nil, nil) }
		let nsRange = NSRange(column.startIndex..<column.endIndex, in: column)
		var thumbnailURL: URL?

		if let match = imageRegex.firstMatch(in: column, options: [], range: nsRange),
		   let range = Range(match.range(at: 1), in: column) {
			let urlString = String(column[range])
			thumbnailURL = makeAbsoluteURL(from: urlString)
		}

		var fullsizeURL: URL?
		if let anchorRange = column.range(of: ")](") {
			let tail = column[anchorRange.upperBound...]
			if let closingParenthesis = tail.firstIndex(of: ")") {
				let candidate = String(tail[..<closingParenthesis])
				fullsizeURL = makeAbsoluteURL(from: candidate)
			}
		}

		let resolvedFullsize = resolveFullsizeImageURL(thumbnail: thumbnailURL, candidate: fullsizeURL)
		return (thumbnailURL, resolvedFullsize)
	}

	private func makeAbsoluteURL(from input: String) -> URL? {
		if let url = URL(string: input), url.scheme != nil {
			return url
		}
		return URL(string: "https://www.bricklink.com\(input)")
	}

	private func makeColorSpecificImageURL(partID: String, colorID: String) -> URL? {
		let trimmedPartID = partID.trimmingCharacters(in: .whitespacesAndNewlines)
		let trimmedColorID = colorID.trimmingCharacters(in: .whitespacesAndNewlines)
		let sanitizedColorID = trimmedColorID == "0" ? "" : trimmedColorID
		guard !trimmedPartID.isEmpty, !sanitizedColorID.isEmpty else { return nil }

		var components = URLComponents()
		components.scheme = "https"
		components.host = "img.bricklink.com"
		components.path = "/ItemImage/PN/\(sanitizedColorID)/\(trimmedPartID).png"
		return components.url
	}

	private func makeColorSpecificThumbnailURL(partID: String, colorID: String) -> URL? {
		let trimmedPartID = partID.trimmingCharacters(in: .whitespacesAndNewlines)
		let trimmedColorID = colorID.trimmingCharacters(in: .whitespacesAndNewlines)
		let sanitizedColorID = trimmedColorID == "0" ? "" : trimmedColorID
		guard !trimmedPartID.isEmpty, !sanitizedColorID.isEmpty else { return nil }

		var components = URLComponents()
		components.scheme = "https"
		components.host = "img.bricklink.com"
		components.path = "/ItemImage/PT/\(sanitizedColorID)/\(trimmedPartID).t1.png"
		return components.url
	}

	private func resolveFullsizeImageURL(thumbnail: URL?, candidate: URL?) -> URL? {
		if let candidate {
			let lowercasedPath = candidate.path.lowercased()
			if lowercasedPath.contains("/catalogitempic.asp"),
			   let components = URLComponents(url: candidate, resolvingAgainstBaseURL: false),
			   let partID = components.queryItems?.first(where: { $0.name.lowercased() == "p" })?.value,
			   !partID.isEmpty {
				var directComponents = URLComponents()
				directComponents.scheme = "https"
				directComponents.host = "www.bricklink.com"
				directComponents.path = "/PL/\(partID).jpg"
				directComponents.query = "0"
				return directComponents.url
			}

			let pathExtension = (candidate.path as NSString).pathExtension
			if !pathExtension.isEmpty {
				return candidate
			}
		}

		if let thumbnail {
			return promoteToHighResolution(thumbnail)
		}

		return candidate
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

	private func categoriesColumn(from line: String) -> String? {
		var columns = line
			.split(separator: "|", omittingEmptySubsequences: false)
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

		while let first = columns.first, first.isEmpty {
			columns.removeFirst()
		}

		while let last = columns.last, last.isEmpty {
			columns.removeLast()
		}

		return columns.first(where: { $0.contains("Catalog") })
	}

	private func preferredMinifigureImageURL(for identifier: String, fallback: URL?) -> URL? {
		let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return fallback }

		let candidates = [trimmed.lowercased(), trimmed.uppercased(), trimmed]

		for candidate in candidates {
			var components = URLComponents()
			components.scheme = "https"
			components.host = "img.bricklink.com"
			components.path = "/ItemImage/MN/0/\(candidate).png"

			if let url = components.url {
				return url
			}
		}

		return fallback
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

	private func sanitizeColorDescription(_ text: String) -> String {
		var cleaned = text
		let fullRange = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
		cleaned = imageRegex.stringByReplacingMatches(
			in: cleaned,
			options: [],
			range: fullRange,
			withTemplate: ""
		)

		cleaned = cleaned.replacingOccurrences(
			of: #"!\[[^\]]*\]"#,
			with: "",
			options: .regularExpression
		)

		return normalizeWhitespace(cleaned)
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
				name = sanitizeSetName(extracted)
			}

			if categories.isEmpty, line.contains("[Catalog]") {
				categories = extractCategories(from: line, baseURL: baseURL)
			}

			if line.contains("catalogItemPic.asp?S="),
			   let preferred = extractImageURLs(from: line).thumbnail,
			   preferred.absoluteString.contains("/S/") {
				thumbnailURL = promoteToHighResolution(preferred)
			} else if thumbnailURL == nil,
					  let candidate = extractImageURLs(from: line).thumbnail {
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
	private let braceContentRegex = try! NSRegularExpression(pattern: #"\{\s*([^}]+)\s*\}"#, options: [])

}

private extension BrickLinkInventoryService {
	func sanitizeSetName(_ raw: String) -> String {
		var result = raw
		let fullRange = NSRange(result.startIndex..<result.endIndex, in: result)
		let matches = braceContentRegex.matches(in: result, options: [], range: fullRange)

		for match in matches.reversed() {
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

			if normalizedToken(precedingWord) == normalizedToken(braceWord) {
				var removalRange = braceRange

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

				removalRange = whitespaceStart..<removalRange.upperBound
				result.removeSubrange(removalRange)
			}
		}

		return result.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
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
