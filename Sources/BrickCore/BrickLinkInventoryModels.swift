import Foundation

public struct BrickLinkInventory: Sendable, Equatable {
	public let setNumber: String
	public let name: String
	public let thumbnailURL: URL?
	public let parts: [BrickLinkPart]
	public let categories: [BrickLinkCategory]

	public init(
		setNumber: String,
		name: String,
		thumbnailURL: URL?,
		parts: [BrickLinkPart],
		categories: [BrickLinkCategory]
	) {
		self.setNumber = setNumber
		self.name = name
		self.thumbnailURL = thumbnailURL
		self.parts = parts
		self.categories = categories
	}
}

public enum BrickLinkPartSection: String, Sendable, Equatable, CaseIterable {
	case regular
	case counterpart
	case extra
	case alternate
}

public struct BrickLinkCategory: Sendable, Equatable {
	public let id: String?
	public let name: String

	public init(id: String?, name: String) {
		self.id = id
		self.name = name
	}
}

public struct BrickLinkPart: Sendable, Equatable {
	public let partID: String
	public let partURL: URL?
	public let name: String
	public let colorName: String
	public let colorID: String
	public let imageURL: URL?
	public let quantity: Int
	public let section: BrickLinkPartSection

	public init(
		partID: String,
		partURL: URL?,
		name: String,
		colorName: String,
		colorID: String,
		imageURL: URL?,
		quantity: Int,
		section: BrickLinkPartSection
	) {
		self.partID = partID
		self.partURL = partURL
		self.name = name
		self.colorName = colorName
		self.colorID = colorID
		self.imageURL = imageURL
		self.quantity = quantity
		self.section = section
	}
}
