import AppKit
import Carbon
import Foundation
import JugglerCore
import SwiftUI

/// Раздел «Хоткеи» окна настроек (UI встраивает его через `SwitchModule.hotkeySettingsView`).
struct HotkeySettingsSection: View {
    @ObservedObject var preferences: HotkeyPreferences
    @StateObject private var recorder: HotkeyRecorderSession

    init(preferences: HotkeyPreferences, center: CarbonHotkeyCenter?) {
        self.preferences = preferences
        _recorder = StateObject(wrappedValue: HotkeyRecorderSession(preferences: preferences, center: center))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(HotkeyAction.allCases, id: \.self) { action in
                HStack(spacing: 10) {
                    Text(action.displayName)
                        .frame(minWidth: 170, alignment: .leading)
                    Spacer(minLength: 8)
                    HotkeyRecorderField(action: action, preferences: preferences, recorder: recorder)
                    Button("По умолчанию") { recorder.reset(action) }
                        .disabled(!preferences.isCustom(action))
                        .help("Вернуть сочетание по умолчанию: \(preferences.defaults[action]?.displayString ?? "—")")
                }
                if let status = preferences.registrationErrors[action] {
                    Text("Не удалось зарегистрировать (код \(status)). Возможно, сочетание занято системой — выберите другое.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            if let message = recorder.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let error = preferences.lastSaveError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Text(aboveTabNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Вернуть все по умолчанию") { recorder.resetAll() }
                    .disabled(preferences.overrides.hotkeys.isEmpty)
            }
        }
        .onDisappear { recorder.cancel() }
    }

    private var aboveTabNote: String {
        let key = KeyCode.displayName(preferences.keyboard.keyAboveTab)
        return String(localized: """
            Хоткеи привязаны к физическим клавишам и работают в любой раскладке (РУ и EN). \
            \(key) — клавиша над Tab, слева от 1. Чтобы назначить сочетание, нажмите на поле и затем нужные клавиши; Esc — отмена.
            """)
    }
}

/// Поле записи одного хоткея: показывает сочетание, по нажатию ждёт новое.
struct HotkeyRecorderField: View {
    let action: HotkeyAction
    @ObservedObject var preferences: HotkeyPreferences
    @ObservedObject var recorder: HotkeyRecorderSession

    var body: some View {
        let isRecording = recorder.recording == action
        Button {
            if isRecording { recorder.cancel() } else { recorder.begin(action) }
        } label: {
            Text(isRecording ? String(localized: "Нажмите сочетание…") : (preferences.assignments[action]?.displayString ?? String(localized: "Не задано")))
                .font(.system(.body, design: .rounded).monospacedDigit())
                .frame(minWidth: 150)
                .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
        }
        .help(isRecording ? String(localized: "Нажмите новое сочетание или Esc для отмены") : String(localized: "Нажмите, чтобы записать новое сочетание"))
    }
}

/// Сеанс записи: пока идёт запись, глобальные хоткеи сняты, а нажатия
/// перехватывает локальный монитор событий окна настроек.
@MainActor
final class HotkeyRecorderSession: ObservableObject {
    @Published private(set) var recording: HotkeyAction?
    @Published private(set) var message: String?

    private let preferences: HotkeyPreferences
    private weak var center: CarbonHotkeyCenter?
    private var monitor: Any?

    init(preferences: HotkeyPreferences, center: CarbonHotkeyCenter?) {
        self.preferences = preferences
        self.center = center
    }

    func begin(_ action: HotkeyAction) {
        if recording == nil { center?.suspend() }
        recording = action
        message = nil
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                let code = event.keyCode
                let flags = event.modifierFlags
                let consumed = MainActor.assumeIsolated { self?.handle(keyCode: code, flags: flags) ?? false }
                return consumed ? nil : event
            }
        }
    }

    func cancel() {
        guard recording != nil else { return }
        finish()
    }

    func reset(_ action: HotkeyAction) {
        cancel()
        preferences.reset(action)
        message = nil
    }

    func resetAll() {
        cancel()
        preferences.resetAll()
        message = nil
    }

    /// `true` — нажатие поглощено записью.
    private func handle(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        guard let action = recording else { return false }
        let modifiers = Self.modifiers(flags)
        let code = UInt32(keyCode)
        if code == KeyCode.escape, modifiers.isEmpty {
            finish()
            return true
        }
        let hotkey = Hotkey(keyCode: code, modifiers: modifiers)
        if let error = preferences.assign(hotkey, to: action) {
            // Остаёмся в режиме записи: можно сразу нажать другое сочетание.
            message = "\(hotkey.displayString): \(error.message)"
            return true
        }
        message = nil
        finish()
        return true
    }

    private func finish() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        center?.resume()
    }

    static func modifiers(_ flags: NSEvent.ModifierFlags) -> HotkeyModifiers {
        var m: HotkeyModifiers = []
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.command) { m.insert(.command) }
        return m
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}
