//
//  RequestGate.swift
//
//
//  A counting semaphore for async callers.
//

import Foundation

/// Caps how many operations may run at once, across every caller that shares it.
///
/// Bounding concurrency at each call site is not enough when the work forms a
/// tree: importing a set walks parts and minifigures at the same time, and each
/// minifigure walks its own parts, so per-call-site limits multiply. The remote
/// server is one shared resource, so the ceiling has to be shared too.
actor RequestGate
{
	private let limit: Int
	private var active = 0
	private var waiters: [CheckedContinuation<Void, Never>] = []

	init(limit: Int)
	{
		self.limit = max(1, limit)
	}

	/// Runs `body` once a permit is free, releasing it however `body` ends.
	func withPermit<T: Sendable>(_ body: @Sendable () async throws -> T) async rethrows -> T
	{
		await acquire()
		defer { release() }

		return try await body()
	}

	/// Permits currently held. Test seam.
	var activeCount: Int
	{
		active
	}

	private func acquire() async
	{
		guard active >= limit else
		{
			active += 1
			return
		}

		// Resumed by `release()`, which hands its permit over directly rather
		// than decrementing — so the count never dips and lets an extra caller in.
		await withCheckedContinuation { continuation in
			waiters.append(continuation)
		}
	}

	private func release()
	{
		guard waiters.isEmpty else
		{
			waiters.removeFirst().resume()
			return
		}

		active -= 1
	}
}
