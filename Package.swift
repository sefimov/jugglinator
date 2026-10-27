// swift-tools-version:5.10
// Сборка только средствами Command Line Tools: без XCTest, Swift Testing,
// #Preview, .xcassets, .storyboard/.xib и сторонних зависимостей.
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
        // Чистая логика: только Foundation. Проверяется из JugglerChecks.
        .target(name: "JugglerCore"),
        // Приложение в меню-баре (SwiftUI + AppKit).
        .executableTarget(name: "Juggler", dependencies: ["JugglerCore"]),
        // Исполняемые проверки: `swift run JugglerChecks`, код 0 — всё прошло.
        .executableTarget(name: "JugglerChecks", dependencies: ["JugglerCore"]),
    ]
)
