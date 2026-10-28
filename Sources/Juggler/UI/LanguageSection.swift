import AppKit
import JugglerCore
import SwiftUI

/// Выбор языка интерфейса, перезапуск после смены. Язык хранится только для Juggler.
@MainActor
final class LanguageController: ObservableObject {
    @Published private(set) var choice: LanguageChoice
    @Published private(set) var restartError: String?

    /// Язык, с которым приложение запущено: смена относительно него требует перезапуска.
    private let launchChoice: LanguageChoice
    private let settings: LanguageSettings

    init(settings: LanguageSettings = LanguageController.appSettings) {
        self.settings = settings
        let current = settings.choice
        self.choice = current
        self.launchChoice = current
    }

    /// Настоящий домен приложения. Под `swift run` пакета нет, берётся имя процесса.
    nonisolated static var appSettings: LanguageSettings {
        LanguageSettings(
            defaults: .standard,
            domain: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName)
    }

    var needsRestart: Bool { choice != launchChoice }

    var canRestart: Bool { Self.relaunch() != nil }

    func select(_ newChoice: LanguageChoice) {
        guard newChoice != choice else { return }
        settings.select(newChoice)
        choice = newChoice
        restartError = nil
    }

    /// Закрывает Juggler и сразу открывает его снова. Задачи уже записаны в tasks.json
    /// (запись при каждом изменении), `applicationWillTerminate` останавливает хоткеи.
    func restartNow() {
        guard let command = Self.relaunch() else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        do {
            try process.run()
        } catch {
            restartError = String(localized: "Не удалось перезапустить Juggler: \(error.localizedDescription)")
            uiLog.error("Перезапуск: \(error.localizedDescription, privacy: .public)")
            return
        }
        NSApp.terminate(nil)
    }

    private static func relaunch() -> (executable: String, arguments: [String])? {
        AppRestart.relaunchCommand(
            bundlePath: Bundle.main.bundleURL.path,
            pid: ProcessInfo.processInfo.processIdentifier)
    }
}

/// Раздел настроек «Язык».
struct LanguageSection: View {
    @StateObject private var controller = LanguageController()

    var body: some View {
        Section("Язык") {
            Picker("Язык интерфейса", selection: Binding(
                get: { controller.choice },
                set: { controller.select($0) })) {
                Text("Как в системе").tag(LanguageChoice.system)
                ForEach(AppLanguage.all) { language in
                    Text(verbatim: language.nativeName).tag(LanguageChoice.language(language.code))
                }
            }
            if controller.needsRestart {
                Text("Язык сменится после перезапуска")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Перезапустить сейчас") {
                    controller.restartNow()
                }
                .disabled(!controller.canRestart)
                if !controller.canRestart {
                    Text("Перезапуск работает только в приложении Juggler.app. Закройте Juggler и запустите его заново.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = controller.restartError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
