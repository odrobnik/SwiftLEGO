//
//  DOMElement+Query.swift
//
//
//  Small query helpers shared by the BrickLink page parsers.
//  The DOM itself comes from SwiftTextHTML.
//

import Foundation
import SwiftTextHTML

extension DOMNode
{
	/// Concatenated text of this node and everything below it.
	///
	/// Deliberately not `DOMNode.text()`, which formats semantically — dropping
	/// `<title>`, turning `<br>` into newlines and laying tables out. These
	/// parsers want the characters as they appear in the cell.
	func textContent() -> String
	{
		guard let element = self as? DOMElement else
		{
			// Text nodes render their own value.
			return text()
		}

		return element.children.map { $0.textContent() }.joined()
	}

	/// `textContent()` with runs of whitespace (including `&nbsp;`) collapsed.
	func collapsedText() -> String
	{
		textContent()
			.replacingOccurrences(of: "\u{00a0}", with: " ")
			.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

extension DOMElement
{
	func attribute(_ name: String) -> String?
	{
		attributes[name] as? String
	}

	var classNames: [String]
	{
		attribute("class")?
			.split(separator: " ")
			.map(String.init) ?? []
	}

	func hasClass(_ name: String) -> Bool
	{
		classNames.contains(name)
	}

	var childElements: [DOMElement]
	{
		children.compactMap { $0 as? DOMElement }
	}

	func descendantElements(named name: String) -> [DOMElement]
	{
		var results: [DOMElement] = []

		if self.name == name
		{
			results.append(self)
		}

		for element in childElements
		{
			results.append(contentsOf: element.descendantElements(named: name))
		}

		return results
	}

	func firstDescendant(where predicate: (DOMElement) -> Bool) -> DOMElement?
	{
		for element in childElements
		{
			if predicate(element)
			{
				return element
			}

			if let match = element.firstDescendant(where: predicate)
			{
				return match
			}
		}

		return nil
	}

	/// First descendant carrying `attributeName`, returning its value.
	func firstAttributeValue(_ attributeName: String) -> String?
	{
		if let value = attribute(attributeName)
		{
			return value
		}

		return firstDescendant(where: { $0.attribute(attributeName) != nil })?
			.attribute(attributeName)
	}
}
