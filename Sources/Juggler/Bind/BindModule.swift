import AppKit
import ApplicationServices
import Foundation
import JugglerCore
import os

// Папка Sources/Juggler/Bind/ принадлежит задаче BIND.
// Сигнатуры функций `BindModule` — контракт с корнем композиции (App/CompositionRoot.swift)
// и самопроверкой (App/SelfTest.swift): тела и типы ниже — заглушки, которые BIND заменяет.

@MainActor
enum BindModule {
    static func makeServices() -> BindServices {
        BindServices(
            contextProvider: StubFrontmostContextProvider(),
            capturer: StubBindingCapturer(),
            activator: StubBindingActivator(),
            permissions: StubPermissions())
    }

    static func makeCurrentChatBinder(model: AppModel, services: BindServices) -> CurrentChatBinding {
        StubCurrentChatBinder()
    }

    /// `Juggler --probe-frontmost`: печатает JSON с контекстом и результатом привязки.
    static func probeFrontmost(arguments: [String]) -> Int32 {
        let services = makeServices()
        let context = services.contextProvider.currentContext()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(context), let json = String(data: data, encoding: .utf8) else {
            return 1
        }
        print(json)
        return 0
    }

    static func selfTest() -> [SelfTestResult] {
        []
    }
}

private let log = Logger(subsystem: JugglerLog.subsystem, category: "bind")

/// Заглушка: только приложение переднего окна, без Accessibility и AppleScript.
private final class StubFrontmostContextProvider: FrontmostContextProviding {
    func currentContext() -> FrontmostContext {
        let app = NSWorkspace.shared.frontmostApplication
        return FrontmostContext(bundleID: app?.bundleIdentifier, appName: app?.localizedName)
    }
}

private final class StubBindingCapturer: BindingCapturing {
    func captureBinding(from context: FrontmostContext) -> BindingCaptureResult {
        .failed("Привязка пока не реализована")
    }
}

private final class StubBindingActivator: BindingActivating {
    func activate(_ binding: TaskBinding) -> ActivationResult {
        log.info("Заглушка активации: \(binding.source.rawValue, privacy: .public)")
        return .failed("Активация пока не реализована")
    }
}

private final class StubPermissions: PermissionsProviding {
    var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }
    func requestAccessibility() {}
}

private final class StubCurrentChatBinder: CurrentChatBinding {
    func bindCurrentChat() {
        log.info("Заглушка «Сделать задачей текущий чат»")
        NSSound.beep()
    }
}
