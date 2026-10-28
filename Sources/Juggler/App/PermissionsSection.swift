import AppKit
import JugglerCore
import SwiftUI

/// Раздел «Разрешения» окна настроек: состояние Accessibility, управления Chrome и Терминалом
/// и кнопки запроса. Сам ничего не запрашивает — только по нажатию кнопки.
struct PermissionsSection: View {
    let environment: AppEnvironment
    @StateObject private var state: PermissionsState

    init(environment: AppEnvironment) {
        self.environment = environment
        _state = StateObject(wrappedValue: PermissionsState(permissions: environment.bind.permissions))
    }

    var body: some View {
        LabeledContent(loc("Универсальный доступ")) {
            HStack {
                statusText(state.accessibilityTrusted ? loc("разрешён") : loc("не разрешён"), ok: state.accessibilityTrusted)
                if !state.accessibilityTrusted {
                    Button(loc("Запросить…")) { state.requestAccessibility() }
                }
            }
        }
        Text(loc("Нужен, чтобы читать заголовки окон, адрес чата Claude и поднимать нужное окно."))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        if state.canManageChrome {
            LabeledContent(loc("Управление Google Chrome")) {
                HStack {
                    statusText(state.chromeText, ok: state.chromeStatus == .granted)
                    if state.chromeStatus != .granted {
                        Button(state.chromeStatus == .notRunning ? loc("Запустить Chrome") : loc("Разрешить…")) { state.requestChrome() }
                    }
                }
            }
            Text(loc("Нужно, чтобы привязывать вкладки и переключаться на них. Без него Juggler открывает адрес заново — в Chrome появляются дубли вкладок."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if state.canManageTerminal {
            LabeledContent(loc("Терминал")) {
                HStack {
                    statusText(state.terminalText, ok: state.terminalStatus == .granted || state.terminalStatus == .noWindow)
                    if state.terminalStatus != .granted, state.terminalStatus != .noWindow {
                        Button(state.terminalStatus == .notRunning ? loc("Запустить Терминал") : loc("Разрешить…")) { state.requestTerminal() }
                    }
                }
            }
            Text(loc("Нужно, чтобы привязывать окно и вкладку Терминала и переключаться именно на них. Без него окно Терминала привязывается как обычное окно, по заголовку, а вкладка не выбирается."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusText(_ text: String, ok: Bool) -> some View {
        Text(text).foregroundStyle(ok ? Color.secondary : Color.orange)
    }
}

/// Состояние разрешений для раздела настроек; обновляется при возврате в приложение.
@MainActor
final class PermissionsState: ObservableObject {
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var chromeStatus: AutomationStatus?
    @Published private(set) var terminalStatus: AutomationStatus?

    private let permissions: PermissionsProviding
    private var observer: NSObjectProtocol?

    init(permissions: PermissionsProviding) {
        self.permissions = permissions
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Раздел Chrome показывается только с рабочими разрешениями BIND.
    var canManageChrome: Bool { permissions is LivePermissions }

    var chromeText: String { Self.text(chromeStatus, notRunning: loc("Chrome не запущен")) }

    /// Строка Терминала — только с рабочими разрешениями BIND и если Терминал установлен.
    var canManageTerminal: Bool {
        permissions is LivePermissions && NSWorkspace.shared.urlForApplication(withBundleIdentifier: KnownBundleIDs.terminal) != nil
    }

    var terminalText: String { Self.text(terminalStatus, notRunning: loc("Терминал не запущен")) }

    private static func text(_ status: AutomationStatus?, notRunning: String) -> String {
        switch status {
        case .granted?: return loc("разрешено")
        case .denied?: return loc("запрещено")
        case .requiresConsent?: return loc("ещё не спрашивали")
        case .notRunning?: return notRunning
        case .noWindow?: return loc("разрешено")
        case .failed?, nil: return loc("неизвестно")
        }
    }

    func refresh() {
        accessibilityTrusted = permissions.isAccessibilityTrusted
        // Проверка без запроса (с коротким таймаутом); Chrome должен быть запущен.
        chromeStatus = (permissions as? LivePermissions)?.chromeAutomationStatus
        terminalStatus = (permissions as? LivePermissions)?.terminalAutomationStatus
    }

    func requestAccessibility() {
        permissions.requestAccessibility()
        refresh()
    }

    func requestChrome() {
        guard let live = permissions as? LivePermissions else { return }
        switch chromeStatus {
        case .denied?:
            // Повторно система не спросит: только инструкция и переход в настройки.
            LivePermissions.showChromeInstructions()
        case .notRunning?:
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: KnownBundleIDs.chrome) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self.refresh() } }
                }
            }
        default:
            live.requestChromeAutomation { [weak self] _ in self?.refresh() }
        }
    }

    func requestTerminal() {
        guard let live = permissions as? LivePermissions else { return }
        switch terminalStatus {
        case .denied?:
            // Повторно система не спросит: только инструкция и переход в настройки.
            LivePermissions.showTerminalInstructions()
        case .notRunning?:
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: KnownBundleIDs.terminal) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self.refresh() } }
                }
            }
        default:
            live.requestTerminalAutomation { [weak self] _ in self?.refresh() }
        }
    }
}
