// swift-tools-version:5.10
// Builds with Command Line Tools only: no XCTest, Swift Testing,
// #Preview, .xcassets, .storyboard/.xib or third-party dependencies.
import PackageDescription

let package = Package(
    name: "Juggler",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Juggler", targets: ["Juggler"]),
        .executable(name: "JugglerChecks", targets: ["JugglerChecks"]),
        .library(name: "JugglerCore", targets: ["JugglerCore"]),
    ],
    targets: [
        // Pure logic: Foundation only. Checked from JugglerChecks.
        .target(name: "JugglerCore"),
        // The menu bar app (SwiftUI + AppKit).
        .executableTarget(name: "Juggler", dependencies: ["JugglerCore"]),
        // Executable checks: `swift run JugglerChecks`, exit code 0 — all passed.
        .executableTarget(name: "JugglerChecks", dependencies: ["JugglerCore"]),
    ]
)
