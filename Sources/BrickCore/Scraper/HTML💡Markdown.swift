//
//  HTML💡Markdown.swift
//
//
//  Created by Oliver Drobnik on 17.05.24.
//

import Foundation

public class HTML💡Markdown
{
	var url: URL?
	
	var data: Data!
	
	public init(url: URL)
	{
		self.url = url
	}
	
	public init(data: Data, url: URL? = nil)
	{
		self.data = data
		self.url = url
	}

	
	public func markdown() async throws -> String
	{
		if data == nil
		{
			do {
				data = try Data(contentsOf: url!)
			}
			catch
			{
				throw ConverterError.retrievingData(error)
			}
		}
		
		let domBuilder = try await DomBuilder(html: data, baseURL: url)
		
		return domBuilder.root!.markdown().trimmingCharacters(in: .whitespacesAndNewlines)
	}
	
	// MARK: - Internal Declarations
	
	enum ConverterError: Error
	{
		case retrievingData(Error)
	}
}
