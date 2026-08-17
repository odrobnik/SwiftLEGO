import Foundation
import Testing
@testable import BrickCore

struct ConcurrentMapTests {

	/// Tracks how many transforms overlapped.
	private actor PeakCounter {
		private var active = 0
		private(set) var peak = 0

		func enter() {
			active += 1
			peak = max(peak, active)
		}

		func leave() {
			active -= 1
		}
	}

	@Test
	func resultsKeepInputOrder() async throws {
		let input = Array(1...50)

		let doubled = try await mapConcurrently(input, limit: 8) { value in
			// Reversing the sleep order would surface any ordering bug.
			try await Task.sleep(for: .milliseconds(value % 5))
			return value * 2
		}

		#expect(doubled == input.map { $0 * 2 })
	}

	@Test
	func concurrencyStaysWithinTheLimit() async throws {
		let counter = PeakCounter()

		_ = try await mapConcurrently(Array(1...40), limit: 4) { _ in
			await counter.enter()
			try await Task.sleep(for: .milliseconds(5))
			await counter.leave()
			return 0
		}

		let peak = await counter.peak
		#expect(peak <= 4, "Expected at most 4 concurrent transforms, saw \(peak).")
	}

	@Test
	func emptyInputDoesNoWork() async throws {
		let results = try await mapConcurrently([Int](), limit: 4) { _ in
			Issue.record("Transform should not run for an empty input.")
			return 0
		}

		#expect(results.isEmpty)
	}

	@Test
	func aThrowingTransformPropagates() async throws {
		struct Boom: Error {}

		await #expect(throws: Boom.self) {
			try await mapConcurrently(Array(1...20), limit: 4) { value in
				if value == 7 { throw Boom() }
				return value
			}
		}
	}

	@Test
	func limitBelowOneIsTreatedAsSerial() async throws {
		let results = try await mapConcurrently([1, 2, 3], limit: 0) { $0 + 1 }

		#expect(results == [2, 3, 4])
	}
}
