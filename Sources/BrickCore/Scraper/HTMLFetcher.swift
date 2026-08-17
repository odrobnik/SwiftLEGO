//
//  HTMLFetcher.swift
//
//
//  Fetches HTML while presenting browser-like request headers.
//

import Foundation

/// Downloads HTML pages using headers that mimic a normal browser navigation,
/// retrying the failures that are worth retrying.
///
/// `Data(contentsOf:)` sends the default `CFNetwork`/`Darwin` user agent, which
/// BrickLink's WAF answers with an empty body — the scraper then has nothing to
/// parse. Supplying a browser user agent and the usual navigation headers gets
/// real markup back from the catalog pages.
enum HTMLFetcher
{
	/// Safari on macOS, the least surprising identity for a page scrape.
	static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

	static let maximumAttempts = 3
	static let requestTimeout: TimeInterval = 30

	/// Ceiling on requests in flight, shared by every caller.
	///
	/// It lives here rather than at the call sites because an import fans out as
	/// a tree — parts and minifigures walk concurrently, and each minifigure
	/// walks its own parts — so per-call-site limits would multiply.
	static let maximumConcurrentRequests = 6

	private static let gate = RequestGate(limit: maximumConcurrentRequests)

	static func data(from url: URL, session: URLSession = .shared) async throws -> Data
	{
		var attempt = 1

		while true
		{
			do
			{
				return try await fetchOnce(url, session: session)
			}
			catch is CancellationError
			{
				throw CancellationError()
			}
			catch
			{
				guard attempt < maximumAttempts, Self.isWorthRetrying(error) else
				{
					throw error
				}

				try await Task.sleep(for: retryDelay(afterAttempt: attempt))
				attempt += 1
			}
		}
	}

	private static func fetchOnce(_ url: URL, session: URLSession) async throws -> Data
	{
		// The permit covers the round trip only — parsing and retry backoff must
		// not hold a slot that another request could be using.
		let request = request(for: url)
		let (data, response) = try await gate.withPermit {
			try await session.data(for: request)
		}

		if let http = response as? HTTPURLResponse,
		   !(200..<300).contains(http.statusCode)
		{
			throw FetchError.unexpectedStatus(http.statusCode, url)
		}

		// A bot-protection interstitial answers 200/202 with a page that has no
		// content of ours in it. Retrying cannot solve a JavaScript challenge, so
		// say so plainly rather than failing later as "nothing to parse".
		if looksLikeBotProtection(data)
		{
			throw FetchError.blockedByBotProtection(url)
		}

		guard !data.isEmpty else
		{
			throw FetchError.emptyResponse(url)
		}

		return data
	}

	private static func looksLikeBotProtection(_ data: Data) -> Bool
	{
		// The challenge page is small; a real catalog page never is.
		guard data.count < 16_384,
			  let markup = String(data: data, encoding: .utf8) else
		{
			return false
		}

		return markup.contains("awsWafCookieDomainList") || markup.contains("gokuProps")
	}

	private static func retryDelay(afterAttempt attempt: Int) -> Duration
	{
		.milliseconds(500 * (1 << (attempt - 1)))
	}

	private static func isWorthRetrying(_ error: Error) -> Bool
	{
		if let fetchError = error as? FetchError
		{
			return fetchError.isWorthRetrying
		}

		guard let urlError = error as? URLError else { return false }

		switch urlError.code
		{
			case .timedOut,
				 .networkConnectionLost,
				 .notConnectedToInternet,
				 .cannotConnectToHost,
				 .dnsLookupFailed,
				 .resourceUnavailable:
				return true

			default:
				return false
		}
	}

	private static func request(for url: URL) -> URLRequest
	{
		var request = URLRequest(url: url)
		request.timeoutInterval = requestTimeout

		request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
		request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
		request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
		request.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
		request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
		request.setValue("none", forHTTPHeaderField: "Sec-Fetch-Site")
		request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")

		return request
	}

	enum FetchError: LocalizedError, Equatable
	{
		case unexpectedStatus(Int, URL)
		case emptyResponse(URL)
		case blockedByBotProtection(URL)

		/// Rate limiting and server faults pass with time; a challenge or a 404
		/// will answer the same way however often it is asked.
		var isWorthRetrying: Bool
		{
			switch self
			{
				case .unexpectedStatus(let status, _):
					return status == 408 || status == 429 || (500..<600).contains(status)

				case .emptyResponse:
					return true

				case .blockedByBotProtection:
					return false
			}
		}

		var errorDescription: String?
		{
			switch self
			{
				case .unexpectedStatus(let status, let url):
					return "\(url.absoluteString) responded with HTTP \(status)."

				case .emptyResponse(let url):
					return "\(url.absoluteString) returned an empty response."

				case .blockedByBotProtection(let url):
					return "BrickLink served a bot-protection challenge for \(url.absoluteString) instead of the page."
			}
		}
	}
}
