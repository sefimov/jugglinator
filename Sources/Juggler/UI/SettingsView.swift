import AppKit
import JugglerCore
import ServiceManagement
import SwiftUI

/// Окно настроек: раздел хоткеев (компонент SWITCH), язык интерфейса, запуск при входе, файл данных.
struct SettingsView: View {
    let environment: AppEnvironment
    @StateObject private var loginItem = LoginItemController()

    var body: some View {
        Form {
            Section(loc("Хоткеи")) {
                SwitchModule.hotkeySettingsView(environment: environment)
            }

            Section(loc("Разрешения")) {
                PermissionsSection(environment: environment)
            }

            LanguageSection()

            Section(loc("Запуск")) {
                Toggle(loc("Запускать Juggler при входе в систему"), isOn: Binding(
                    get: { loginItem.state.isOn },
                    set: { loginItem.setEnabled($0) }))
                if let explanation = loginItem.state.explanation {
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = loginItem.errorText {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if loginItem.state.needsSystemSettings {
                    Button(loc("Открыть «Объекты входа»")) {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
            }

            Section(loc("Данные")) {
                LabeledContent(loc("Файл задач")) {
                    Text(environment.model.store.fileURL.path)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                Button(loc("Показать в Finder")) {
                    revealDataFile()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .frame(minHeight: 380)
        .navigationTitle(loc("Настройки Juggler"))
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }

    private func revealDataFile() {
        let file = environment.model.store.fileURL
        if FileManager.default.fileExists(atPath: file.path) {
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } else {
            let directory = file.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(directory)
        }
    }
}

/// Запуск при входе в систему через `SMAppService.mainApp`.
@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var state: LoginItemState
    @Published private(set) var errorText: String?

    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
        self.state = Self.map(service.status)
    }

    func refresh() {
        state = Self.map(service.status)
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            errorText = nil
        } catch {
            errorText = enabled
                ? loc("Не удалось включить запуск при входе: \(error.localizedDescription)")
                : loc("Не удалось выключить запуск при входе: \(error.localizedDescription)")
            uiLog.error("SMAppService: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    static func map(_ status: SMAppService.Status) -> LoginItemState {
        switch status {
        case .enabled: return .enabled
        case .notRegistered: return .notRegistered
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }
}
