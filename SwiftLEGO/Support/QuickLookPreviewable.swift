import Foundation
import SwiftUI

protocol QuickLookPreviewable: Identifiable {
    var quickLookID: AnyHashable { get }
    var quickLookPreferredURL: URL? { get }
    var quickLookFallbackURL: URL? { get }
    var quickLookPreviewBaseName: String { get }
}

#if canImport(BrickCore)
import BrickCore

extension Part: QuickLookPreviewable {
    var quickLookID: AnyHashable { persistentModelID }

    var quickLookPreferredURL: URL? {
        highResolutionImageURL ?? imageURL
    }

    var quickLookFallbackURL: URL? {
        guard let preferred = quickLookPreferredURL,
              preferred != imageURL else {
            return nil
        }
        return imageURL
    }

    var quickLookPreviewBaseName: String {
        "Part \(partID)"
    }
}

extension BrickSet: QuickLookPreviewable {
    var quickLookID: AnyHashable { persistentModelID }

    var quickLookPreferredURL: URL? {
        thumbnailURL
    }

    var quickLookFallbackURL: URL? {
        nil
    }

    var quickLookPreviewBaseName: String {
        "\(setNumber) \(name)"
    }
}

extension Minifigure: QuickLookPreviewable {
    var quickLookID: AnyHashable { persistentModelID }

    var quickLookPreferredURL: URL? {
        imageURL
    }

    var quickLookFallbackURL: URL? {
        nil
    }

    var quickLookPreviewBaseName: String {
        "Minifigure \(identifier)"
    }
}

extension OrderPart: QuickLookPreviewable {
    var quickLookID: AnyHashable { persistentModelID }

    var quickLookPreferredURL: URL? {
        imageURL
    }

    var quickLookFallbackURL: URL? {
        nil
    }

    var quickLookPreviewBaseName: String {
        "Order Part \(partID)"
    }
}
#endif
