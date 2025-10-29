import Foundation
import SwiftData

@Model
final class BrickColor {
    @Attribute(.unique) var brickLinkColorID: Int
    var brickLinkName: String
    var legoColorName: String?
    var legoColorID: Int?
    var hexColor: String?
    var updatedAt: Date

    init(
        brickLinkColorID: Int,
        brickLinkName: String,
        legoColorName: String?,
        legoColorID: Int?,
        hexColor: String?
    ) {
        self.brickLinkColorID = brickLinkColorID
        self.brickLinkName = brickLinkName
        self.legoColorName = legoColorName
        self.legoColorID = legoColorID
        self.hexColor = hexColor
        self.updatedAt = Date()
    }
}
