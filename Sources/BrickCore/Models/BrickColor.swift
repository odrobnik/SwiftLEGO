import Foundation
import SwiftData

@Model
public final class BrickColor {
    @Attribute(.unique) public var brickLinkColorID: Int
    public var brickLinkName: String
    public var legoColorName: String?
    public var legoColorID: Int?
    public var hexColor: String?
    public var updatedAt: Date

    public init(
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
