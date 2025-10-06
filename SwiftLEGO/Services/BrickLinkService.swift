import Foundation

struct BrickLinkSetPayload: Sendable {
    let setNumber: String
    let name: String
    let thumbnailURL: URL?
    let parts: [BrickLinkPartPayload]
}

struct BrickLinkPartPayload: Sendable {
    let partID: String
    let colorID: String
    let quantityNeeded: Int
}

actor BrickLinkService {
    enum ServiceError: Error {
        case invalidResponse
        case unsupportedHTMLStructure
    }

    func fetchSetDetails(for setNumber: String) async throws -> BrickLinkSetPayload {
        // TODO: Implement BrickLink scraping logic.
        // For the MVP scaffolding we provide stubbed data so UI flows can be exercised.
        try await Task.sleep(nanoseconds: 200_000_000)
        return BrickLinkSetPayload(
            setNumber: setNumber,
            name: "Placeholder \(setNumber)",
            thumbnailURL: nil,
            parts: [
                BrickLinkPartPayload(partID: "3001", colorID: "5", quantityNeeded: 4),
                BrickLinkPartPayload(partID: "3003", colorID: "1", quantityNeeded: 10)
            ]
        )
    }
}
