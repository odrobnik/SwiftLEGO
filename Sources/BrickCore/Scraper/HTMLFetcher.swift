//
//  HTMLFetcher.swift
//
//
//  Fetches HTML while presenting browser-like request headers.
//

import Foundation

/// Downloads HTML pages using headers that mimic a normal browser navigation.
///
/// `Data(contentsOf:)` sends the default `CFNetwork`/`Darwin` user agent, which
/// BrickLink's WAF answers with an empty body — the scraper then has nothing to
/// parse. Supplying a browser user agent and the usual navigation headers gets
/// real markup back from the catalog and color-guide pages.
enum HTMLFetcher
{
	/// Safari on macOS, the least surprising identity for a page scrape.
	static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

	static func data(from url: URL) async throws -> Data
	{
		let (data, response) = try await URLSession.shared.data(for: request(for: url))

		guard let http = response as? HTTPURLResponse else
		{
			return data
		}

		guard (200..<300).contains(http.statusCode) else
		{
			throw FetchError.unexpectedStatus(http.statusCode, url)
		}

		return data
	}

	private static func request(for url: URL) -> URLRequest
	{
		var request = URLRequest(url: url)

		request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
		request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
		request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
		request.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
		request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
		request.setValue("none", forHTTPHeaderField: "Sec-Fetch-Site")
		request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")

		return request
	}

	enum FetchError: LocalizedError
	{
		case unexpectedStatus(Int, URL)

		var errorDescription: String?
		{
			switch self
			{
				case .unexpectedStatus(let status, let url):
					return "\(url.absoluteString) responded with HTTP \(status)."
			}
		}
	}
}
