import Foundation

/// Serves canned responses to a `URLSession` so fetch behaviour can be tested
/// without touching the network.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
	struct Response {
		let statusCode: Int
		let body: Data

		init(statusCode: Int = 200, body: Data = Data("<html><body>ok</body></html>".utf8)) {
			self.statusCode = statusCode
			self.body = body
		}

		static func html(_ markup: String, statusCode: Int = 200) -> Response {
			Response(statusCode: statusCode, body: Data(markup.utf8))
		}
	}

	/// Consumed front to back, one per request; the last entry repeats.
	nonisolated(unsafe) private static var queue: [Response] = []
	nonisolated(unsafe) private static var recordedRequests = 0
	private static let lock = NSLock()

	static func reset(with responses: [Response]) {
		lock.lock()
		defer { lock.unlock() }
		queue = responses
		recordedRequests = 0
	}

	static var requestCount: Int {
		lock.lock()
		defer { lock.unlock() }
		return recordedRequests
	}

	private static func nextResponse() -> Response {
		lock.lock()
		defer { lock.unlock() }
		recordedRequests += 1

		if queue.count > 1 {
			return queue.removeFirst()
		}

		return queue.first ?? Response()
	}

	static func makeSession() -> URLSession {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [StubURLProtocol.self]
		return URLSession(configuration: configuration)
	}

	override class func canInit(with request: URLRequest) -> Bool { true }

	override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

	override func startLoading() {
		let stub = Self.nextResponse()
		let response = HTTPURLResponse(
			url: request.url!,
			statusCode: stub.statusCode,
			httpVersion: "HTTP/1.1",
			headerFields: ["Content-Type": "text/html"]
		)!

		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: stub.body)
		client?.urlProtocolDidFinishLoading(self)
	}

	override func stopLoading() {}
}
