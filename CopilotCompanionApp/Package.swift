// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CopilotCompanionApp",
    platforms: [.macOS(.v11)],
    products: [
        .library(name: "CopilotCompanionApp", targets: ["CopilotCompanionApp"]),
    ],
    targets: [
        .target(name: "CopilotCompanionApp"),
    ]
)
