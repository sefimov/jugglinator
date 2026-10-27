import AppKit
import SwiftUI

/// Точка входа. Ключи командной строки обрабатываются до запуска SwiftUI:
/// - `--self-test` — самопроверка всех компонентов без окон и запросов разрешений;
/// - `--probe-frontmost` — печать JSON с контекстом переднего окна (BIND).
@main
enum JugglerEntry {
    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--self-test") {
            exit(SelfTest.run())
        }
        if arguments.contains("--probe-frontmost") {
            exit(BindModule.probeFrontmost(arguments: arguments))
        }
        JugglerApp.main()
    }
}

/// Приложение в меню-баре. Сцены (меню-бар и настройки) строит UI в `UIModule.scenes`.
struct JugglerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        UIModule.scenes(environment: AppEnvironment.shared)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Без .app и LSUIElement (`swift run Juggler`) скрываем значок в Dock вручную.
        NSApp.setActivationPolicy(.accessory)
        AppEnvironment.shared.start()
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        AppEnvironment.shared.stop()
    }
}
