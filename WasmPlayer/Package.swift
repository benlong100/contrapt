// swift-tools-version: 6.0
//
// The browser bridge for exported websites: compiles HyperTalkEngine to
// WebAssembly and installs `window.ContraptEngine` for player.js.
//
// This is a SEPARATE package (not a target in HyperTalk/) so the app's Xcode
// dependency graph never touches JavaScriptKit — this package is only built
// by Scripts/build-web-engine.sh with the wasm Swift SDK. See EXPORT-WASM.md.
//

import PackageDescription

let package = Package(
    name: "WasmPlayer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../HyperTalk"),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit", from: "0.59.0"),
    ],
    targets: [
        .executableTarget(
            name: "ContraptEngineWasm",
            dependencies: [
                .product(name: "HyperTalkEngine", package: "HyperTalk"),
                .product(name: "JavaScriptKit", package: "JavaScriptKit"),
                .product(name: "JavaScriptEventLoop", package: "JavaScriptKit"),
            ],
            swiftSettings: [
                // The bridge is single-threaded by construction (wasm has one
                // thread; JSClosure callbacks all run on it), so soften Swift 6
                // strict-concurrency diagnostics around the JS boundary.
                .swiftLanguageMode(.v5)
            ]
        ),
    ]
)
