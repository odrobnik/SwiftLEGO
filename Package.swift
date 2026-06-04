// swift-tools-version: 5.10

import PackageDescription

let package = Package(
	name: "BrickCore",
	platforms: [
		.macOS(.v14),
		.iOS(.v17)
	],
	products: [
		.library(
			name: "BrickCore",
			targets: ["BrickCore"]
		)
	],
	dependencies: [
		.package(url: "https://github.com/Cocoanetics/SwiftText.git", from: "1.1.9"),
		.package(url: "https://github.com/CoreOffice/XMLCoder.git", from: "0.17.1")
	],
	targets: [
		.target(
			name: "BrickCore",
			dependencies: [
				.product(name: "SwiftTextHTML", package: "SwiftText"),
				"XMLCoder"
			],
			path: "Sources/BrickCore"
		),
		.testTarget(
			name: "BrickCoreTests",
			dependencies: [
				"BrickCore"
			],
			path: "Tests/BrickCoreTests"
		)
	]
)
