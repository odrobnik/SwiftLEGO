//
//  DomNode.swift
//
//
//  Created by Oliver Drobnik on 18.05.24.
//

import Foundation

public class DOMElement: DOMNode 
{
	// MARK: - Public Properties
	
	public let name: String
	public let attributes: [AnyHashable: Any]
	public var children: [DOMNode]
	
	// MARK: - Initialization
	
	init(name: String, attributes: [AnyHashable: Any] = [:]) {
		self.name = name
		self.attributes = attributes
		self.children = []
	}
	
	// MARK: - Public Functions
	
	func addChild(_ child: DOMNode) 
	{
		children.append(child)
	}
	
	public func markdown() -> String 
	{
		if ["script", "style", "iframe", "nav", "meta", "link", "title", "select", "input", "button", "noscript", "footer"].contains(name)
		{
			return ""
		}
		
		var result = ""
		
		switch name
		{
			case "p", "div":
				
				var content = ""
				
				for child in children
				{
					if child.isBlockLevelElement
					{
						content.ensureTwoTrailingNewlines()
					}
					
					content += child.markdown()
				}
				
				content = content.trimmingCharacters(in: .whitespacesAndNewlines)
				
				guard !content.isEmpty else {
					return ""
				}
				result += content
				
			case "b", "strong":
				let content = children.map { $0.markdown() }.joined()
				result += handleInlineElement(content, with: "**")
				
			case "i", "em":
				let content = children.map { $0.markdown() }.joined()
				result += handleInlineElement(content, with: "*")
				
			case "a":
				let href = attributes["href"] as? String ?? ""
				
				let content = children.map { $0.markdown() }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
				
				if href.contains("#"),
				   let components = URLComponents(string: href),
				   components.fragment != nil
				{
					result += content
				}
				else if !href.isEmpty, !content.isEmpty
				{
					result += "[" + content + "]" + "(\(href))"
				}
				
			case "img":
				let src = attributes["src"] as? String ?? ""
				let alt = attributes["alt"] as? String ?? "Image"
				
				if !src.isEmpty, !src.hasPrefix("data:")
				{
					result += "![\(alt)](\(src))"
				}
				
			case "figcaption":
				let content = children.map { $0.markdown() }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
				
				result = "\n" + content
				
			case "br":
				result += "\n"
				
			case "ul":
				for child in children {
					let childText = child.markdown()
					if !childText.isEmpty {
						result += "- " + childText + "\n"
					}
				}
				
			case "ol":
				var index = 1
				for child in children {
					let childText = child.markdown()
					if !childText.isEmpty {
						result += "\(index). " + childText + "\n"
						index += 1
					}
				}
				
			case "li":
				let content = children.map { $0.markdown() }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
				guard !content.isEmpty else {
					return ""
				}
				result += content
				
			case "h1":
				result += "# " + children.map { $0.markdown() }.joined()
				
			case "h2":
				result += "## " + children.map { $0.markdown() }.joined()
				
			case "h3":
				result += "### " + children.map { $0.markdown() }.joined()
				
			case "h4":
				result += "#### " + children.map { $0.markdown() }.joined()
				
			case "h5":
				result += "##### " + children.map { $0.markdown() }.joined()
				
			case "h6":
				result += "###### " + children.map { $0.markdown() }.joined()
				
		case "table":
			let columns = buildTableColumns()
			result += formatTable(columns: columns)
			
		case "tr":
				let cells = children.map { $0.markdown().trimmingCharacters(in: .whitespacesAndNewlines) }
				result += cells.joined(separator: " | ") + "\n"
				
		case "th":
			let content = children.map { $0.markdown() }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
			let normalized = normalizeTableCellContent(content)
			result += "**" + normalized + "**"
			
		case "td":
			let content = children.map { $0.markdown() }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
			let normalized = normalizeTableCellContent(content)
			result += normalized
				
			case "blockquote":
				let blockquoteContent = children.map { $0.markdown().trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\n")
				result += "> " + blockquoteContent.replacingOccurrences(of: "\n", with: "\n> ")
				
			case "pre":
				
				let preContent: String
				
				if let code = children.first as? DOMElement, code.name == "code", children.count == 1
				{
					preContent = code.children.map { $0.markdown() }.joined().trimmingCharacters(in: .newlines)
				}
				else
				{
					preContent = children.map { $0.markdown() }.joined().trimmingCharacters(in: .newlines)
				}
				
				result += "```\n" + preContent + "\n```\n"

			case "code":
				// This is an inline code element, so handle it with single backticks
				let content = children.map { $0.markdown() }.joined()
				result += handleInlineElement(content, with: "`")

				
			default:
				
				result += children.map { $0.markdown() }.joined()
		}
		
		// Ensure \n\n at the end of block-level elements
		
		if isBlockLevelElement
		{
			result.ensureTwoTrailingNewlines()
		}
		
		return result
	}
	
	private func handleInlineElement(_ content: String, with markdownSyntax: String) -> String {
		// Find the range of leading whitespace characters
		let leadingWhitespaceRange = content.range(of: "^\\s+", options: .regularExpression)
		
		// Extract leading whitespace if it exists
		let leadingWhitespace = leadingWhitespaceRange.map { String(content[$0]) } ?? ""
		
		// Find the range of trailing whitespace characters
		let trailingWhitespaceRange = content.range(of: "\\s+$", options: .regularExpression)
		
		// Extract trailing whitespace if it exists
		let trailingWhitespace = trailingWhitespaceRange.map { String(content[$0]) } ?? ""
		
		// Trim the content without the leading and trailing whitespace
		let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
		
		// Construct the result with the leading whitespace, markdown syntax, trimmed content, markdown syntax, and trailing whitespace
		let result = leadingWhitespace + markdownSyntax + trimmedContent + markdownSyntax + trailingWhitespace
		
		return result
	}
	
	// Builds an array of columns with the resolved markdown of the cells
	private func buildTableColumns() -> [[String]] {
		var columns: [[String]] = []
		var maxColumns = 0

		for child in children {
			if let row = child as? DOMElement, row.name == "tr" {
				var currentRow: [String] = []
				for cell in row.children {
					let cellContent = cell.markdown().trimmingCharacters(in: .whitespacesAndNewlines)
					currentRow.append(cellContent)
				}
				maxColumns = max(maxColumns, currentRow.count)
				columns.append(currentRow)
			}
		}

		// Ensure all rows have the same number of columns
		for i in 0..<columns.count {
			while columns[i].count < maxColumns {
				columns[i].append("")
			}
		}

		return columns
	}
	
	// Formats the table based on the maximum column widths
	private func formatTable(columns: [[String]]) -> String {
		guard !columns.isEmpty else {
			return ""
		}

		var maxColumnWidths = Array(repeating: 0, count: columns.first?.count ?? 0)

		for row in columns {
			for (i, cell) in row.enumerated() {
				let lines = cell.components(separatedBy: "\n")
				let longestLine = lines.map { $0.count }.max() ?? 0
				if maxColumnWidths.count <= i {
					maxColumnWidths.append(longestLine)
				} else {
					maxColumnWidths[i] = max(maxColumnWidths[i], longestLine)
				}
			}
		}

		// Markdown separators need at least three characters per column
		let separatorWidths = maxColumnWidths.map { max($0, 3) }

		var formattedTable = ""

		for (rowIndex, row) in columns.enumerated() {
			let cellLines = row.map { $0.components(separatedBy: "\n") }
			let lineCount = cellLines.map { $0.count }.max() ?? 1
			
			for lineIndex in 0..<lineCount {
				var formattedRow = "|"
				for (i, lines) in cellLines.enumerated() {
					let line = lineIndex < lines.count ? lines[lineIndex] : ""
					let paddedContent = line.padding(toLength: maxColumnWidths[i], withPad: " ", startingAt: 0)
					formattedRow += " \(paddedContent) |"
				}
				formattedTable += formattedRow + "\n"
			}
			
			if rowIndex == 0 {
				let separatorLine = separatorWidths.map { String(repeating: "-", count: $0) }.joined(separator: " | ")
				formattedTable += "| " + separatorLine + " |\n"
			}
		}

		return formattedTable
	}

	private func normalizeTableCellContent(_ content: String) -> String {
		var normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
		normalized = normalized.replacingOccurrences(of: "\n{2,}", with: "\n", options: .regularExpression)
		var lines = normalized.components(separatedBy: "\n")
		lines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
		while let first = lines.first, first.isEmpty { lines.removeFirst() }
		while let last = lines.last, last.isEmpty { lines.removeLast() }
		return lines.joined(separator: "\n")
	}
}
