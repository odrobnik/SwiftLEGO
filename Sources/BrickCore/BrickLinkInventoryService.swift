import Foundation

public final class BrickLinkInventoryService {

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
		return try parse(markdown: markdown, setNumber: setNumber, baseURL: url)
	}

	// MARK: - Parsing

	private func parse(markdown: String, setNumber: String, baseURL: URL) throws -> BrickLinkInventory {
		let lines = markdown.components(separatedBy: .newlines)

		guard let tableHeaderIndex = lines.firstIndex(where: { $0.contains("| **Image**") }) else {
			throw InventoryError.partsTableNotFound
		}

		let metadata = parseMetadata(from: lines)

		var parts: [BrickLinkPart] = []
		var index = tableHeaderIndex + 2 // skip header and separator lines

		var currentSection: BrickLinkPartSection = .regular

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

		if line.contains("**Extra Items:**") {
			currentSection = .extra
			index += 1
			continue
		}

		if line.contains("**Counterpart Items:**") {
			currentSection = .counterpart
			index += 1
			continue
		}

		if line.contains("**Alternate Items:**") {
			currentSection = .alternate
			index += 1
			continue
		}

		if line.contains("**Regular Items:**") {
			currentSection = .regular
			index += 1
			continue
		}

			if line.localizedCaseInsensitiveContains("Parts:") {
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

			if !columns.contains(where: { $0.contains("catalog/catalogitem.page?P=") }) {
				index += 1
				continue
			}

			do {
				let part = try parsePartRow(columns: columns, baseURL: baseURL, section: currentSection)
				parts.append(part)
			} catch {
				throw InventoryError.malformedRow(line)
			}

			index += 1
		}

		let name = metadata.name ?? "Set \(setNumber)"
		return BrickLinkInventory(
			setNumber: setNumber,
			name: name,
			thumbnailURL: metadata.thumbnailURL,
			parts: parts
		)
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

	private func parseMetadata(from lines: [String]) -> (name: String?, thumbnailURL: URL?) {
		var name: String?
		var thumbnailURL: URL?

		for line in lines {
			if name == nil, let extracted = extractSetName(from: line) {
				name = extracted
			}

			if line.contains("catalogItemPic.asp?S="),
			   let preferred = extractImageURL(from: line),
			   preferred.absoluteString.contains("/S/") {
				thumbnailURL = promoteToHighResolution(preferred)
			} else if thumbnailURL == nil,
					  let candidate = extractImageURL(from: line) {
				thumbnailURL = promoteToHighResolution(candidate)
			}

			if name != nil, thumbnailURL != nil {
				break
			}
		}

		return (name, thumbnailURL)
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
