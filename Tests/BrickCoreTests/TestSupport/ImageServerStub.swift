import Foundation

/// Answers requests the way BrickLink's image server does: a URL it has an
/// image for serves that image, every other URL is a 404.
final class ImageServerStub: URLProtocol, @unchecked Sendable {
	/// A 1 x 1 PNG.
	static let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=")!

	nonisolated(unsafe) private static var bodies: [URL: Data] = [:]
	nonisolated(unsafe) private static var requests: [URL] = []
	private static let lock = NSLock()

	static func reset(serving bodies: [URL: Data] = [:]) {
		lock.lock()
		defer { lock.unlock() }
		Self.bodies = bodies
		requests = []
	}

	/// Every URL asked for since the last reset, in order.
	static var requestedURLs: [URL] {
		lock.lock()
		defer { lock.unlock() }
		return requests
	}

	static func makeSession() -> URLSession {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [ImageServerStub.self]
		return URLSession(configuration: configuration)
	}

	private static func record(_ url: URL) -> Data? {
		lock.lock()
		defer { lock.unlock() }
		requests.append(url)
		return bodies[url]
	}

	override class func canInit(with request: URLRequest) -> Bool { true }

	override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

	override func startLoading() {
		let url = request.url!
		let body = Self.record(url)
		let response = HTTPURLResponse(
			url: url,
			statusCode: body == nil ? 404 : 200,
			httpVersion: "HTTP/1.1",
			headerFields: ["Content-Type": body == nil ? "text/html" : "image/png"]
		)!

		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: body ?? Data("<html><body>Not Found</body></html>".utf8))
		client?.urlProtocolDidFinishLoading(self)
	}

	override func stopLoading() {}
}
