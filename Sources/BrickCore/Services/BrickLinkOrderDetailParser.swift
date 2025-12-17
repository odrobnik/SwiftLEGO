import Foundation

public struct BrickLinkOrderDetail: Sendable, Equatable {
    public let orderID: String?
    public let parts: [BrickLinkOrderPart]

    public init(orderID: String?, parts: [BrickLinkOrderPart]) {
        self.orderID = orderID
        self.parts = parts
    }
}

public struct BrickLinkOrderPart: Sendable, Equatable {
    public enum ItemType: String, Codable, Sendable {
        case part
        case minifigure
    }

    public let itemType: ItemType
    public let partID: String
    public let colorID: String
    public let name: String?
    public let quantity: Int
    public let imageURL: URL?

    public init(
        itemType: ItemType,
        partID: String,
        colorID: String,
        name: String?,
        quantity: Int,
        imageURL: URL?
    ) {
        self.itemType = itemType
        self.partID = partID
        self.colorID = colorID
        self.name = name
        self.quantity = quantity
        self.imageURL = imageURL
    }
}

public final class BrickLinkOrderDetailParser {
    public enum OrderDetailError: Error {
        case invalidResponse
    }

    public init() {}

    public func parseOrderDetail(
        htmlData: Data,
        baseURL: URL?
    ) async throws -> BrickLinkOrderDetail {
        let domBuilder = try await DomBuilder(html: htmlData, baseURL: baseURL)
        guard let root = domBuilder.root else {
            throw OrderDetailError.invalidResponse
        }

        let orderID = parseOrderID(in: root)
        let parts = parseParts(in: root, baseURL: baseURL)

        return BrickLinkOrderDetail(orderID: orderID, parts: parts)
    }

    private func parseOrderID(in root: DOMElement) -> String? {
        let text = textContent(of: root)
        let pattern = "Order #([0-9]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1,
              let idRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[idRange])
    }

    private func parseParts(in root: DOMElement, baseURL: URL?) -> [BrickLinkOrderPart] {
        let rows = descendantElements(named: "tr", from: root)
        var parts: [BrickLinkOrderPart] = []
        parts.reserveCapacity(rows.count)

        for row in rows {
            if let part = parsePartRow(row, baseURL: baseURL) {
                parts.append(part)
            }
        }

        return parts
    }

    private func parsePartRow(_ row: DOMElement, baseURL: URL?) -> BrickLinkOrderPart? {
        let cellElements = row.children.compactMap { $0 as? DOMElement }.filter { $0.name == "td" }
        guard cellElements.count >= 5 else { return nil }

        guard let imageElement = firstDescendant(named: "img", in: row),
              let src = imageElement.attributes["src"] as? String else {
            return nil
        }

        guard let partInfo = parsePartIdentifier(from: src, baseURL: baseURL) else {
            return nil
        }

        let quantityText = textContent(of: cellElements[4])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")

        guard let quantity = Int(quantityText) else { return nil }

        let name = parseName(from: imageElement)
        let imageURL = URL(string: src, relativeTo: baseURL)

        return BrickLinkOrderPart(
            itemType: partInfo.itemType,
            partID: partInfo.partID,
            colorID: partInfo.colorID,
            name: name,
            quantity: quantity,
            imageURL: imageURL
        )
    }

    private func parsePartIdentifier(
        from src: String,
        baseURL: URL?
    ) -> (partID: String, colorID: String, itemType: BrickLinkOrderPart.ItemType)? {
        guard let url = URL(string: src, relativeTo: baseURL) else { return nil }
        let components = url.pathComponents
        if let index = components.firstIndex(where: { $0.caseInsensitiveCompare("P") == .orderedSame }) {
            guard components.count > index + 2 else { return nil }

            let colorID = components[index + 1]
            let filename = components[index + 2]
            let partID = (filename as NSString).deletingPathExtension
            guard !partID.isEmpty else { return nil }

            return (partID: partID, colorID: colorID, itemType: .part)
        }

        if let index = components.firstIndex(where: { $0.caseInsensitiveCompare("M") == .orderedSame }) {
            guard components.count > index + 1 else { return nil }

            let filename = components[index + 1]
            let partID = (filename as NSString).deletingPathExtension
            guard !partID.isEmpty else { return nil }

            return (partID: partID, colorID: "0", itemType: .minifigure)
        }

        return nil
    }

    private func parseName(from imageElement: DOMElement) -> String? {
        guard let raw = imageElement.attributes["title"] as? String ?? imageElement.attributes["alt"] as? String else {
            return nil
        }
        if let range = raw.range(of: "Name:") {
            let trimmed = raw[range.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizeWhitespace(String(trimmed))
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return normalizeWhitespace(trimmed)
    }

    private func descendantElements(named name: String, from root: DOMElement) -> [DOMElement] {
        var results: [DOMElement] = []
        if root.name == name {
            results.append(root)
        }
        for child in root.children {
            guard let element = child as? DOMElement else { continue }
            results.append(contentsOf: descendantElements(named: name, from: element))
        }
        return results
    }

    private func firstDescendant(named name: String, in root: DOMElement) -> DOMElement? {
        for child in root.children {
            if let element = child as? DOMElement {
                if element.name == name {
                    return element
                }
                if let match = firstDescendant(named: name, in: element) {
                    return match
                }
            }
        }
        return nil
    }

    private func textContent(of node: DOMNode) -> String {
        if let textNode = node as? DOMText {
            return textNode.text
        }
        if let element = node as? DOMElement {
            return element.children.map { textContent(of: $0) }.joined()
        }
        return ""
    }

    private func normalizeWhitespace(_ string: String) -> String {
        string
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
