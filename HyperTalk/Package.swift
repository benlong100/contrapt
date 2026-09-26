// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HyperTalk",
    // A platform floor where Swift concurrency (async/await, used since the
    // interpreter suspends for `answer`/`ask`) is natively available.
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "HyperTalk", targets: ["HyperTalk"]),
        // The headless runtime the exported website hosts (later compiled to
        // Wasm): the interpreter driving an in-memory stack, with DOM effects
        // queued for JavaScript to apply.
        .library(name: "HyperTalkEngine", targets: ["HyperTalkEngine"]),
    ],
    targets: [
        .target(name: "HyperTalk"),
        .testTarget(name: "HyperTalkTests", dependencies: ["HyperTalk"]),
        .target(name: "HyperTalkEngine", dependencies: ["HyperTalk"]),
        .testTarget(name: "HyperTalkEngineTests", dependencies: ["HyperTalkEngine"]),
    ]
)
