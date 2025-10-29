import Foundation

public struct BrickLinkColorGuideEntry: Sendable, Equatable {
    public let brickLinkColorID: Int
    public let brickLinkName: String
    public let legoColorName: String?
    public let legoColorID: Int?
    public let hexColor: String?

    public init(
        brickLinkColorID: Int,
        brickLinkName: String,
        legoColorName: String?,
        legoColorID: Int?,
        hexColor: String?
    ) {
        self.brickLinkColorID = brickLinkColorID
        self.brickLinkName = brickLinkName
        self.legoColorName = legoColorName
        self.legoColorID = legoColorID
        self.hexColor = hexColor
    }
}

public actor BrickLinkColorGuideService {
    public enum ColorGuideError: Error {
        case invalidResponse
        case tableNotFound
    }

    public init() {}

    public func fetchColorGuide(locale: String = "en-us") async throws -> [BrickLinkColorGuideEntry] {
        let localeLowercased = locale.lowercased()
        guard let url = URL(string: "https://v2.bricklink.com/\(localeLowercased)/catalog/color-guide") else {
            throw ColorGuideError.invalidResponse
        }

        let data = try Data(contentsOf: url)
        return try await parseColorGuide(htmlData: data, baseURL: url)
    }

    public func parseColorGuide(htmlData: Data, baseURL: URL) async throws -> [BrickLinkColorGuideEntry] {
        let domBuilder = try await DomBuilder(html: htmlData, baseURL: baseURL)
        guard let root = domBuilder.root else {
            throw ColorGuideError.invalidResponse
        }

        var entries: [BrickLinkColorGuideEntry] = []

        for row in root.descendantElements(named: "tr") {
            guard let entry = parseRow(row) else { continue }
            entries.append(entry)
        }

        guard !entries.isEmpty else {
            throw ColorGuideError.tableNotFound
        }

        return entries
    }

    private func parseRow(_ row: DOMElement) -> BrickLinkColorGuideEntry? {
        let cellElements = row.children.compactMap { $0 as? DOMElement }.filter { $0.name == "td" }

        guard cellElements.count >= 8 else { return nil }

        let nameCell = cellElements[1]
        guard let legoInfoElement = nameCell.firstDescendant(where: { element in
            element.name == "span" && element.textContent().contains("LEGO Color:")
        }) else {
            return nil
        }

        guard let nameElement = nameCell.firstDescendant(where: { element in
            element.name == "p"
        }) else {
            return nil
        }

        let brickLinkName = nameElement.textContent().trimmingCharacters(in: .whitespacesAndNewlines)

        let legoInfoText = legoInfoElement.textContent()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00a0}", with: " ")

        let legoDetails = Self.parseLegoColorDetails(from: legoInfoText)

        let idCell = cellElements.last!
        let idText = idCell.textContent()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")

        guard let brickLinkID = Int(idText) else { return nil }

        let swatchCell = cellElements[0]
        let hexValue = Self.hexColor(from: swatchCell)

        return BrickLinkColorGuideEntry(
            brickLinkColorID: brickLinkID,
            brickLinkName: brickLinkName,
            legoColorName: legoDetails.name,
            legoColorID: legoDetails.id,
            hexColor: hexValue
        )
    }

    private static func parseLegoColorDetails(from text: String) -> (name: String?, id: Int?) {
        guard text.contains("LEGO Color:") else { return (nil, nil) }

        var content = text.replacingOccurrences(of: "LEGO Color:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if content.hasPrefix("<!-- -->") {
            content.removeFirst("<!-- -->".count)
            content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let hyphenRange = content.range(of: "-", options: .backwards) {
            let possibleID = content[hyphenRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            let namePart = content[..<hyphenRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let legoID = Int(possibleID)
            return (namePart, legoID)
        } else {
            return (content.isEmpty ? nil : content, nil)
        }
    }

    private static func hexColor(from cell: DOMElement) -> String? {
        guard let styleValue = cell.attributes["style"] as? String else { return nil }
        let components = styleValue.components(separatedBy: ";")
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("--bl-castor-table-swatch-with-image-background-color:") {
                if let hexPart = trimmed.split(separator: ":").last {
                    let candidate = hexPart.trimmingCharacters(in: .whitespacesAndNewlines)
                    if candidate.hasPrefix("#") {
                        return candidate
                    }
                }
            }
        }

        return nil
    }
}

private extension DOMElement {
    func descendantElements(named name: String) -> [DOMElement] {
        var results: [DOMElement] = []
        if self.name == name {
            results.append(self)
        }

        for child in children {
            guard let element = child as? DOMElement else { continue }
            results.append(contentsOf: element.descendantElements(named: name))
        }

        return results
    }

    func firstDescendant(where predicate: (DOMElement) -> Bool) -> DOMElement? {
        for child in children {
            if let element = child as? DOMElement {
                if predicate(element) {
                    return element
                }
                if let match = element.firstDescendant(where: predicate) {
                    return match
                }
            }
        }

        return nil
    }
}

private extension DOMNode {
    func textContent() -> String {
        if let textNode = self as? DOMText {
            return textNode.text
        } else if let element = self as? DOMElement {
            return element.children.map { $0.textContent() }.joined()
        } else {
            return ""
        }
    }
}
