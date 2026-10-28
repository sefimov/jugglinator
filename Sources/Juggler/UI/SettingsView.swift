import AppKit
import JugglerCore
import ServiceManagement
import SwiftUI

/// Окно настроек: раздел хоткеев (компонент SWITCH), запуск при входе, файл данных.
struct SettingsView: View {
    let environment: AppEnvironment
    @StateObject private var loginItem = LoginItemController()

    var body: some View {
        Form {
            Section("Хоткеи") {
                SwitchModule.hotkeySettingsView(environment: environment)
            }

            Section("Разрешения") {
                PermissionsSection(environment: environment)
            }

            Section("Запуск") {
                Toggle("Запускать Juggler при входе в систему", isOn: Binding(
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
                    Button("Открыть «Объекты входа»") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
            }

            Section("Данные") {
                LabeledContent("Файл задач") {
                    Text(environment.model.store.fileURL.path)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                Button("Показать в Finder") {
                    revealDataFile()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .frame(minHeight: 380)
        .navigationTitle("Настройки Juggler")
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
                ? String(localized: "Не удалось включить запуск при входе: \(error.localizedDescription)")
                : String(localized: "Не удалось выключить запуск при входе: \(error.localizedDescription)")
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
