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
		.package(url: "https://github.com/odrobnik/HTMLParser.git", branch: "main"),
		.package(url: "https://github.com/CoreOffice/XMLCoder.git", from: "0.17.1")
	],
	targets: [
		.target(
			name: "BrickCore",
			dependencies: [
				"HTMLParser",
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
