import Foundation

/// The pattern number of a printed part, and the spellings BrickLink may have
/// moved it to.
///
/// BrickLink pads a family's pattern numbers once it outgrows them: the round
/// 2 x 2 tiles went from `14769pb328` to `14769pb0328`. The old number is then
/// gone for good — its catalog page, its search and its images all answer "not
/// found", and the new item does not list it as an alternate — so the padded
/// spellings are the only way from a stored number to the item.
enum BrickLinkItemNumber {
	/// `14769pb0421L` → `14769pb`, `0421`, `L`. Only the `pb`/`px` print codes
	/// count: in `973pb1234c01` the trailing `c01` is an assembly, not a print.
	private static let patternNumber = #/(?<prefix>.*?\d.*?p[bx])(?<digits>\d+)(?<suffix>[a-z]*)/#
		.ignoresCase()

	/// The spellings `itemNumber` may have moved to, nearest first: its pattern
	/// number padded by one more digit, and on up to four digits.
	///
	/// `14769pb328` → `14769pb0328`; `3626bpb05` → `3626bpb005`, `3626bpb0005`.
	/// Empty for a number without a pattern number.
	static func renumberingCandidates(for itemNumber: String) -> [String] {
		guard let match = itemNumber.wholeMatch(of: patternNumber) else { return [] }

		let digits = match.output.digits
		let widths = (digits.count + 1)...max(4, digits.count + 1)

		return widths.map { width in
			let padding = String(repeating: "0", count: width - digits.count)
			return "\(match.output.prefix)\(padding)\(digits)\(match.output.suffix)"
		}
	}

	/// A lowercased spelling that every padding of the same pattern number
	/// shares, so a stored part can find its renumbered self: `14769pb0328` and
	/// `14769pb328` both read `14769pb328`.
	static func matchingKey(for itemNumber: String) -> String {
		guard let match = itemNumber.wholeMatch(of: patternNumber) else { return itemNumber.lowercased() }

		let significantDigits = match.output.digits.drop(while: { $0 == "0" })
		let digits = significantDigits.isEmpty ? "0" : significantDigits

		return "\(match.output.prefix)\(digits)\(match.output.suffix)".lowercased()
	}
}
