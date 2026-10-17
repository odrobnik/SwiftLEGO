import Testing
@testable import BrickCore

struct BrickLinkItemNumberTests {
	@Test(arguments: [
		("14769pb328", ["14769pb0328"]),
		("14769pb421L", ["14769pb0421L"]),
		("3626bpb05", ["3626bpb005", "3626bpb0005"]),
		("3068bpx1", ["3068bpx01", "3068bpx001", "3068bpx0001"]),
		("973pb1234", ["973pb01234"])
	])
	func patternNumbersArePaddedOneDigitAtATime(itemNumber: String, candidates: [String]) {
		#expect(BrickLinkItemNumber.renumberingCandidates(for: itemNumber) == candidates)
	}

	/// Plain molds, minifigures, and assemblies whose print is not the last number.
	@Test(arguments: ["3001", "sw0001a", "973pb1234c01", "pb123", ""])
	func numbersWithoutATrailingPatternNumberHaveNoCandidates(itemNumber: String) {
		#expect(BrickLinkItemNumber.renumberingCandidates(for: itemNumber).isEmpty)
	}

	@Test
	func everyPaddingOfAPatternNumberSharesOneMatchingKey() {
		let keys = ["14769pb328", "14769pb0328", "14769PB0328"].map(BrickLinkItemNumber.matchingKey(for:))

		#expect(Set(keys) == ["14769pb328"])
		#expect(BrickLinkItemNumber.matchingKey(for: "14769pb0421L") == "14769pb421l")
	}

	@Test
	func distinctItemsKeepDistinctMatchingKeys() {
		#expect(BrickLinkItemNumber.matchingKey(for: "14769pb328") != BrickLinkItemNumber.matchingKey(for: "14769pb329"))
		#expect(BrickLinkItemNumber.matchingKey(for: "14769pb0003") != BrickLinkItemNumber.matchingKey(for: "14769pb0030"))
		#expect(BrickLinkItemNumber.matchingKey(for: "3001") == "3001")
	}
}
