//
//  DomText.swift
//
//
//  Created by Oliver Drobnik on 18.05.24.
//

import Foundation

class DOMText: DOMNode {
	let name: String
	let text: String
	let preserveWhitespace: Bool
	
	init(text: String, preserveWhitespace: Bool = false) {
		self.name = "#text"
		self.text = text
		self.preserveWhitespace = preserveWhitespace
	}
	
	func markdown() -> String {
		if preserveWhitespace {
			return text
		} else {
			// Compress whitespace to a single space, but keep leading and trailing spaces
			let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
			let leadingSpace = text.hasPrefix(" ") ? " " : ""
			let trailingSpace = text.hasSuffix(" ") ? " " : ""
			return leadingSpace + trimmed.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) + trailingSpace
		}
	}
}
