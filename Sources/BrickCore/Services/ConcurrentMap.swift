import Foundation

/// Maps `items` concurrently while keeping at most `limit` transforms in flight,
/// returning results in the order of the input.
///
/// A set inventory can list hundreds of rows, and a plain task group would put a
/// request for every one of them on the wire at once — enough to look like an
/// attack and get throttled. This keeps a sliding window instead: the group is
/// primed with `limit` tasks and starts another only as one finishes.
///
/// Throws `CancellationError` when the calling task is cancelled, rather than
/// returning whatever the transforms produced by then: they may swallow the
/// cancellation (the inventory fetches are `try?`) and hand back a degraded
/// value, which would pass for a complete result.
func mapConcurrently<Element: Sendable, Transformed: Sendable>(
	_ items: [Element],
	limit: Int,
	_ transform: @escaping @Sendable (Element) async throws -> Transformed
) async throws -> [Transformed] {
	guard !items.isEmpty else { return [] }

	let limit = max(1, limit)
	var results: [Transformed?] = Array(repeating: nil, count: items.count)

	try await withThrowingTaskGroup(of: (Int, Transformed).self) { group in
		var next = 0

		while next < min(limit, items.count) {
			let index = next
			group.addTask { (index, try await transform(items[index])) }
			next += 1
		}

		while let (index, transformed) = try await group.next() {
			results[index] = transformed

			guard next < items.count else { continue }

			// Neither `next()` nor `addTask` notices cancellation: the refill
			// would go on starting children that are cancelled from birth.
			try Task.checkCancellation()

			let index = next
			group.addTask { (index, try await transform(items[index])) }
			next += 1
		}
	}

	// The last window can finish after a cancellation without refilling.
	try Task.checkCancellation()

	return results.compactMap { $0 }
}
