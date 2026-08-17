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
		// Pinned to the 2.1.0 commit rather than `from: "2.1.0"`.
		//
		// SwiftText 2.x declares its ZIPFoundation dependency by revision, and
		// SwiftPM refuses to resolve a package *at a version* whose own
		// dependencies are revision-based. Pinning here sidesteps that, because
		// the restriction does not apply to the root package. Move back to a
		// version requirement once SwiftText expresses ZIPFoundation as one.
		.package(
			url: "https://github.com/Cocoanetics/SwiftText.git",
			revision: "8093c0d3b22754bdbde895230f0f72dbfde6c69d" // 2.1.0
		),
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
