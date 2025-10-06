//
//  DOMNode.swift
//  
//
//  Created by Oliver Drobnik on 18.05.24.
//

import Foundation

public protocol DOMNode
{
	var name: String { get }
	func markdown() -> String
}

fileprivate let blockLevelElements: Set<String> = ["p", "div", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre", "figure", "table", "noscript"]

extension DOMNode
{
	var isBlockLevelElement: Bool
	{
		return blockLevelElements.contains(name)
	}
}
