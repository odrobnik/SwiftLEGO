import Foundation
import Testing
@testable import BrickCore

struct RequestGateTests {

	private actor PeakCounter {
		private var active = 0
		private(set) var peak = 0
		private(set) var completed = 0

		func enter() {
			active += 1
			peak = max(peak, active)
		}

		func leave() {
			active -= 1
			completed += 1
		}
	}

	@Test
	func permitsNeverExceedTheLimit() async throws {
		let gate = RequestGate(limit: 3)
		let counter = PeakCounter()

		await withTaskGroup(of: Void.self) { group in
			for _ in 0..<30 {
				group.addTask {
					await gate.withPermit {
						await counter.enter()
						try? await Task.sleep(for: .milliseconds(5))
						await counter.leave()
					}
				}
			}
		}

		let peak = await counter.peak
		let completed = await counter.completed

		#expect(peak <= 3, "Expected at most 3 permits, saw \(peak).")
		#expect(completed == 30)
	}

	/// A permit handed to a waiter must not also be counted as released, or the
	/// gate would leak capacity every time it is contended.
	@Test
	func permitsAreFullyReturnedAfterContention() async throws {
		let gate = RequestGate(limit: 2)

		await withTaskGroup(of: Void.self) { group in
			for _ in 0..<20 {
				group.addTask {
					await gate.withPermit {
						try? await Task.sleep(for: .milliseconds(2))
					}
				}
			}
		}

		let active = await gate.activeCount
		#expect(active == 0, "Gate should be idle once every permit is returned, saw \(active).")
	}

	@Test
	func aThrowingBodyStillReturnsItsPermit() async throws {
		struct Boom: Error {}

		let gate = RequestGate(limit: 1)

		await #expect(throws: Boom.self) {
			try await gate.withPermit { throw Boom() }
		}

		let active = await gate.activeCount
		#expect(active == 0)

		// The gate is still usable.
		let value = await gate.withPermit { 42 }
		#expect(value == 42)
	}

	@Test
	func limitBelowOneStillAdmitsOneCaller() async throws {
		let gate = RequestGate(limit: 0)

		let value = await gate.withPermit { "ran" }

		#expect(value == "ran")
	}
}
