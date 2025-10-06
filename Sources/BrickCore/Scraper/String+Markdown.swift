//
//  String+Markdown.swift
//  
//
//  Created by Oliver Drobnik on 12.06.24.
//

extension String 
{
	/// Make sure that the receiver has two trailing newlines for a paragraph break
	///
	mutating func ensureTwoTrailingNewlines()
	{
		guard !isEmpty else
		{
			return
		}
		
		var trailingNewlines = 0
		
		for char in self.reversed() {
			if char == "\n" {
				trailingNewlines += 1
			} else {
				break
			}
		}
		
		if trailingNewlines == 0 {
			self += "\n\n"
		} else if trailingNewlines == 1 {
			self += "\n"
		}
	}
}
