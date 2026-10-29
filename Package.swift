// swift-tools-version:5.10
// Builds with Command Line Tools only: no XCTest, Swift Testing,
// #Preview, .xcassets, .storyboard/.xib or third-party dependencies.
import PackageDescription

let package = Package(
    name: "Jugglinator",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Jugglinator", targets: ["Jugglinator"]),
        .executable(name: "JugglerChecks", targets: ["JugglerChecks"]),
        .library(name: "JugglerCore", targets: ["JugglerCore"]),
    ],
    targets: [
        // Pure logic: Foundation only. Checked from JugglerChecks.
        .target(name: "JugglerCore"),
        // The menu bar app (SwiftUI + AppKit).
        .executableTarget(name: "Jugglinator", dependencies: ["JugglerCore"]),
        // Executable checks: `swift run JugglerChecks`, exit code 0 — all passed.
        .executableTarget(name: "JugglerChecks", dependencies: ["JugglerCore"]),
    ]
)
