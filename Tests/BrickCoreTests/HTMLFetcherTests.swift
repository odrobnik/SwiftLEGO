import Foundation
import Testing
@testable import BrickCore

/// Serialized because `StubURLProtocol` queues its responses globally.
@Suite(.serialized)
struct HTMLFetcherTests {

	private static let url = URL(string: "https://www.bricklink.com/v2/catalog/catalogitem.page?S=43245-1")!

	/// The interstitial BrickLink serves in place of catalogItemInv.asp.
	private static let challengePage = """
	<!DOCTYPE html><html><head><script>
	window.awsWafCookieDomainList = ['www.bricklink.com'];
	window.gokuProps = { "key": "AQID" };
	</script></head><body></body></html>
	"""

	@Test
	func successfulResponseIsReturned() async throws {
		StubURLProtocol.reset(with: [.html("<html><body>hello</body></html>")])

		let data = try await HTMLFetcher.data(from: Self.url, session: StubURLProtocol.makeSession())

		#expect(String(decoding: data, as: UTF8.self).contains("hello"))
		#expect(StubURLProtocol.requestCount == 1)
	}

	@Test
	func botProtectionIsReportedAndNotRetried() async throws {
		StubURLProtocol.reset(with: [.html(Self.challengePage, statusCode: 202)])

		await #expect(throws: HTMLFetcher.FetchError.blockedByBotProtection(Self.url)) {
			try await HTMLFetcher.data(from: Self.url, session: StubURLProtocol.makeSession())
		}

		// Retrying cannot solve a JavaScript challenge.
		#expect(StubURLProtocol.requestCount == 1)
	}

	@Test
	func emptyBodyIsAnErrorRatherThanEmptyData() async throws {
		StubURLProtocol.reset(with: [.init(statusCode: 202, body: Data())])

		await #expect(throws: HTMLFetcher.FetchError.self) {
			try await HTMLFetcher.data(from: Self.url, session: StubURLProtocol.makeSession())
		}
	}

	@Test
	func transientServerErrorIsRetriedThenSucceeds() async throws {
		StubURLProtocol.reset(with: [
			.html("nope", statusCode: 503),
			.html("<html><body>recovered</body></html>")
		])

		let data = try await HTMLFetcher.data(from: Self.url, session: StubURLProtocol.makeSession())

		#expect(String(decoding: data, as: UTF8.self).contains("recovered"))
		#expect(StubURLProtocol.requestCount == 2)
	}

	@Test
	func rateLimitIsRetriedUpToTheAttemptLimit() async throws {
		StubURLProtocol.reset(with: [.html("slow down", statusCode: 429)])

		await #expect(throws: HTMLFetcher.FetchError.self) {
			try await HTMLFetcher.data(from: Self.url, session: StubURLProtocol.makeSession())
		}

		#expect(StubURLProtocol.requestCount == HTMLFetcher.maximumAttempts)
	}

	@Test
	func clientErrorIsNotRetried() async throws {
		StubURLProtocol.reset(with: [.html("gone", statusCode: 404)])

		await #expect(throws: HTMLFetcher.FetchError.unexpectedStatus(404, Self.url)) {
			try await HTMLFetcher.data(from: Self.url, session: StubURLProtocol.makeSession())
		}

		#expect(StubURLProtocol.requestCount == 1)
	}

	@Test
	func retryClassificationMatchesStatusSemantics() {
		#expect(HTMLFetcher.FetchError.unexpectedStatus(429, Self.url).isWorthRetrying)
		#expect(HTMLFetcher.FetchError.unexpectedStatus(503, Self.url).isWorthRetrying)
		#expect(HTMLFetcher.FetchError.unexpectedStatus(408, Self.url).isWorthRetrying)
		#expect(!HTMLFetcher.FetchError.unexpectedStatus(404, Self.url).isWorthRetrying)
		#expect(!HTMLFetcher.FetchError.blockedByBotProtection(Self.url).isWorthRetrying)
		#expect(HTMLFetcher.FetchError.emptyResponse(Self.url).isWorthRetrying)
	}
}
