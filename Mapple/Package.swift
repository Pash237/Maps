// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "Mapple",
	platforms: [
		.iOS(.v13)
	],
    products: [
        .library(
            name: "Mapple",
            targets: ["Mapple"]),
    ],
    dependencies: [
		.package(url: "https://github.com/kean/Nuke", from: "12.1.4"),
		.package(url: "https://github.com/b3ll/Motion", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "Mapple",
            dependencies: [
				.product(name: "Nuke", package: "Nuke"),
				.product(name: "Motion", package: "Motion"),
			])
    ]
)
