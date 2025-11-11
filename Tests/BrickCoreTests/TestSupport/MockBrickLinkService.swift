import Foundation
@testable import BrickCore

actor MockBrickLinkService: BrickLinkSetProviding {
    enum MockError: Error {
        case missingPayload
    }

    private var storedPayloads: [String: BrickLinkSetPayload] = [:]
    private var requests: [String] = []

    func fetchSetDetails(for setNumber: String) async throws -> BrickLinkSetPayload {
        requests.append(setNumber)
        guard let payload = storedPayloads[setNumber] else {
            throw MockError.missingPayload
        }
        return payload
    }

    func setPayload(_ payload: BrickLinkSetPayload, for setNumber: String) {
        storedPayloads[setNumber] = payload
    }

    func recordedRequests() -> [String] {
        requests
    }
}
