// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HyperTalk",
    products: [
        .library(name: "HyperTalk", targets: ["HyperTalk"])
    ],
    targets: [
        .target(name: "HyperTalk"),
        .testTarget(name: "HyperTalkTests", dependencies: ["HyperTalk"]),
    ]
)
