import AppKit
import JugglerCore
import SwiftUI

/// Язык интерфейса: выбор, переключение текстов Juggler на ходу и перезапуск для системных надписей.
/// Язык хранится только для Juggler.
///
/// Один экземпляр на приложение (`shared`): меню, окно настроек и иконка в меню-баре следят за
/// `language` и перерисовываются, как только он меняется (`followsLanguage()`).
@MainActor
final class LanguageController: ObservableObject {
    static let shared = LanguageController()

    @Published private(set) var choice: LanguageChoice
    /// Код языка, на котором сейчас показываются тексты Juggler.
    @Published private(set) var language: String
    @Published private(set) var restartError: String?

    /// Выбор, с которым приложение запущено: по нему AppKit и Info.plist выбрали язык своих надписей.
    private let launchChoice: LanguageChoice
    private let settings: LanguageSettings
    private let localizer: Localizer
    private let systemLanguages: () -> [String]

    /// `settings`, `localizer` и `systemLanguages` подменяются в самопроверке: настоящие настройки
    /// и язык приложения она не трогает.
    init(settings: LanguageSettings = .app,
         localizer: Localizer = .shared,
         systemLanguages: @escaping () -> [String] = { LanguageSettings.systemPreferredLanguages() }) {
        self.settings = settings
        self.localizer = localizer
        self.systemLanguages = systemLanguages
        let current = settings.choice
        self.choice = current
        self.launchChoice = current
        let code = LanguageSettings.code(for: current, systemPreferred: systemLanguages())
        self.language = code
        localizer.setLanguage(code)
    }

    /// Системные надписи AppKit (заголовок окна настроек, стандартные кнопки) и Info.plist
    /// всё ещё на языке запуска: их сменит только перезапуск.
    var needsRestart: Bool { choice != launchChoice }

    var canRestart: Bool { Self.relaunch() != nil }

    /// Запомнить выбор и сразу переключить тексты Juggler.
    func select(_ newChoice: LanguageChoice) {
        guard newChoice != choice else { return }
        settings.select(newChoice)
        choice = newChoice
        restartError = nil
        refreshLanguage()
    }

    /// Пересчитать язык (для «Как в системе» — по текущим языкам системы) и переключить тексты.
    func refreshLanguage() {
        let code = LanguageSettings.code(for: choice, systemPreferred: systemLanguages())
        localizer.setLanguage(code)
        if code != language { language = code }
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
            restartError = loc("Не удалось перезапустить Juggler: \(error.localizedDescription)")
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

/// Перерисовка на новом языке: при смене языка поддерево строится заново (`id`), так что все
/// `loc(...)` внутри снова вычисляются; локаль окружения — того же языка.
private struct FollowsLanguage: ViewModifier {
    @ObservedObject var controller: LanguageController

    func body(content: Content) -> some View {
        content
            .id(controller.language)
            .environment(\.locale, Locale(identifier: controller.language))
    }
}

extension View {
    /// Корень окна или меню, тексты которого должны сразу сменить язык.
    @MainActor
    func followsLanguage() -> some View {
        modifier(FollowsLanguage(controller: .shared))
    }
}

/// Раздел настроек «Язык».
struct LanguageSection: View {
    @ObservedObject private var controller = LanguageController.shared

    var body: some View {
        Section(loc("Язык")) {
            Picker(loc("Язык интерфейса"), selection: Binding(
                get: { controller.choice },
                set: { controller.select($0) })) {
                Text(loc("Как в системе")).tag(LanguageChoice.system)
                ForEach(AppLanguage.all) { language in
                    Text(verbatim: language.nativeName).tag(LanguageChoice.language(language.code))
                }
            }
            if controller.needsRestart {
                Text(loc("Тексты Juggler уже на новом языке. Системные надписи macOS — заголовок окна настроек, стандартные кнопки, тексты запросов разрешений — сменятся после перезапуска."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(loc("Перезапустить сейчас")) {
                    controller.restartNow()
                }
                .disabled(!controller.canRestart)
                if !controller.canRestart {
                    Text(loc("Перезапуск работает только в приложении Juggler.app. Закройте Juggler и запустите его заново."))
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
        .onAppear { controller.refreshLanguage() }
    }
}
