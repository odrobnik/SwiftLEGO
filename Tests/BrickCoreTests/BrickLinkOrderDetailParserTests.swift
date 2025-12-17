import Foundation
import Testing
@testable import BrickCore

struct BrickLinkOrderDetailParserTests {
    @Test
    func parseOrderDetailFixture() async throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fixturesDirectory = testsDirectory.deletingLastPathComponent().appendingPathComponent("Fixtures")
        let fileURL = fixturesDirectory.appendingPathComponent("orderDetail.htm")

        let data = try Data(contentsOf: fileURL)
        let parser = BrickLinkOrderDetailParser()

        let detail = try await parser.parseOrderDetail(
            htmlData: data,
            baseURL: URL(string: "https://www.bricklink.com")!
        )

        let partsByType = Dictionary(grouping: detail.parts, by: \.itemType)
        print("Order ID: \(detail.orderID ?? "nil")")
        print("Items: \(detail.parts.count)")
        print("Parts: \(partsByType[.part]?.count ?? 0), Minifigures: \(partsByType[.minifigure]?.count ?? 0)")
        for part in detail.parts.prefix(5) {
            let name = part.name ?? ""
            print("- \(part.itemType.rawValue) \(part.partID) color \(part.colorID) qty \(part.quantity) name \(name)")
        }

        #expect(detail.orderID == "29841663")
        #expect(detail.parts.count == 1378)

        let sample = try #require(detail.parts.first { part in
            part.partID == "30377" && part.colorID == "11" && part.itemType == .part
        })
        #expect(sample.quantity == 2)
        #expect(sample.name == "Arm Mechanical, Battle Droid")

        let alternate = try #require(detail.parts.first { part in
            part.partID == "30377" && part.colorID == "85" && part.itemType == .part
        })
        #expect(alternate.quantity == 3)

        let minifigure = try #require(detail.parts.first { part in
            part.partID == "hp137" && part.itemType == .minifigure
        })
        #expect(minifigure.quantity == 1)
    }
}
