import AppKit
import JugglerCore
import SwiftUI

/// Interface language: choosing it, switching Juggler texts on the fly, and relaunching for system labels.
/// The language is stored for Juggler only.
///
/// One instance per app (`shared`): the menu, the settings window and the menu bar icon observe
/// `language` and redraw as soon as it changes (`followsLanguage()`).
@MainActor
final class LanguageController: ObservableObject {
    static let shared = LanguageController()

    @Published private(set) var choice: LanguageChoice
    /// Code of the language Juggler texts are currently shown in.
    @Published private(set) var language: String
    @Published private(set) var restartError: String?

    /// The choice the app was launched with: AppKit and Info.plist picked their labels' language from it.
    private let launchChoice: LanguageChoice
    private let settings: LanguageSettings
    private let localizer: Localizer
    private let systemLanguages: () -> [String]

    /// `settings`, `localizer` and `systemLanguages` are substituted in the self-test: it does not touch
    /// the real settings or the app language.
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

    /// AppKit system labels (settings window title, standard buttons) and Info.plist
    /// are still in the launch language: only a relaunch changes them.
    var needsRestart: Bool { choice != launchChoice }

    var canRestart: Bool { Self.relaunch() != nil }

    /// Remember the choice and switch Juggler texts immediately.
    func select(_ newChoice: LanguageChoice) {
        guard newChoice != choice else { return }
        settings.select(newChoice)
        choice = newChoice
        restartError = nil
        refreshLanguage()
    }

    /// Recompute the language (for "Same as system" — from the current system languages) and switch texts.
    func refreshLanguage() {
        let code = LanguageSettings.code(for: choice, systemPreferred: systemLanguages())
        localizer.setLanguage(code)
        if code != language { language = code }
    }

    /// Quits Juggler and immediately reopens it. Tasks are already saved to tasks.json
    /// (saved on every change), `applicationWillTerminate` stops the hotkeys.
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

/// Redraw in the new language: when the language changes the subtree is rebuilt (`id`), so all
/// `loc(...)` calls inside are re-evaluated; the environment locale uses the same language.
private struct FollowsLanguage: ViewModifier {
    @ObservedObject var controller: LanguageController

    func body(content: Content) -> some View {
        content
            .id(controller.language)
            .environment(\.locale, Locale(identifier: controller.language))
    }
}

extension View {
    /// Root of a window or menu whose texts must switch language immediately.
    @MainActor
    func followsLanguage() -> some View {
        modifier(FollowsLanguage(controller: .shared))
    }
}

/// The "Language" settings section.
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
