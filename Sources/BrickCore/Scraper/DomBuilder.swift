//
//  DomBuilder.swift
//
//
//  Created by Oliver Drobnik on 18.05.24.
//

import Foundation
import HTMLParser

public final class DomBuilder
{
	// MARK: - Public Properties
	
	public private(set) var root: DOMElement?
	
	// MARK: - Internal State
	
	fileprivate var currentElement: DOMElement!
	fileprivate var elementStack: [DOMElement] = []
	
	
	let baseURL: URL?
	
	// MARK: - Initialization
	
	init(html: Data, baseURL: URL?) async throws
	{
		self.baseURL = baseURL
		
		try await parseHTML(html)
	}
	
	// MARK: - Async Parsing
	
	private func parseHTML(_ html: Data) async throws {
		let parser = HTMLParser(data: html, encoding: .utf8, options: [.noWarning, .noError, .noNet, .recover])
		
		for try await event in parser.parse() {
			switch event {
				case .startElement(let elementName, let attributes):
					handleStartElement(elementName, attributes: attributes)
					
				case .characters(let string):
					handleCharacters(string)
					
				case .endElement(let elementName):
					handleEndElement(elementName)
					
				default:
					break
					
			}
		}
	}
	
	// MARK: - Event Handlers
	
	private func handleStartElement(_ elementName: String, attributes attributeDict: [String: String]) {
		var attributeDict = attributeDict
		
		if elementName == "a"
		{
			if let href = attributeDict["href"]
			{
				if href.hasPrefix("javascript:")
				{
					attributeDict["href"] = nil
				}
				else if let url = URL(string: href, relativeTo: baseURL)
				{
					attributeDict["href"] = url.absoluteString
				}
			}
		}
		
		let element = DOMElement(name: elementName, attributes: attributeDict)
		
		if let current = currentElement
		{
			current.addChild(element)
			elementStack.append(current)
		}
		else
		{
			root = element
		}
		
		currentElement = element
	}
	
	private func handleCharacters(_ string: String) {
		let isWhiteSpace = string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		
		if (["pre", "code"].contains(currentElement.name))
		{
			let textNode = DOMText(text: string, preserveWhitespace: true)
			currentElement?.addChild(textNode)
		}
		else
		{
			if isWhiteSpace,
			   let currentElement, ["ul", "ol", "body", "div", "blockquote", "tr", "table"].contains(currentElement.name)
			{
				// don't add white space in those block-nodes here, because it should only be inline like LI, P
			}
			else
			{
				let textNode = DOMText(text: string, preserveWhitespace: false)
				currentElement?.addChild(textNode)
			}
		}
	}
	
	private func handleEndElement(_ elementName: String) {
		guard !elementStack.isEmpty else
		{
			currentElement = nil
			return
		}
		
		currentElement = elementStack.removeLast()
	}
}
