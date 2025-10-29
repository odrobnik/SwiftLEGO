import Foundation
import Testing
@testable import BrickCore

struct BrickLinkColorGuideServiceTests {
    @Test
    func parseColorGuideFixture() async throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fixturesDirectory = testsDirectory.deletingLastPathComponent().appendingPathComponent("Fixtures")
        let fileURL = fixturesDirectory.appendingPathComponent("bricklink-color-guide-en-us.html")

        let data = try Data(contentsOf: fileURL)
        let service = BrickLinkColorGuideService()

        let entries = try await service.parseColorGuide(
            htmlData: data,
            baseURL: URL(string: "https://v2.bricklink.com/en-us/catalog/color-guide")!
        )

        #expect(entries.count == 212)

        let first = try #require(entries.first)
        #expect(first.brickLinkColorID == 1)
        #expect(first.brickLinkName == "White")
        #expect(first.legoColorName == "White")
        #expect(first.legoColorID == 1)
        #expect(first.hexColor == "#FFFFFF")

        let last = try #require(entries.last)
        #expect(last.brickLinkColorID == 219)
        #expect(last.brickLinkName == "Mx Foil Orange")
        #expect(last.legoColorName == "Orange")
        #expect(last.legoColorID == 91)
        #expect(last.hexColor == "#F7AD63")
    }
}
