import AppKit
import Carbon
import Foundation
import JugglerCore
import SwiftUI

// The Sources/Juggler/Switch/ folder belongs to the SWITCH task.
// `SwitchModule` function signatures are a contract with the composition root (App/CompositionRoot.swift),
// UI (the hotkeys section in settings) and the self-test (App/SelfTest.swift).
//
// Contents:
//   CarbonHotkeyCenter   — global hotkeys (Carbon), re-registration when assignments change;
//   HotkeyPreferences    — defaults by keyboard type + custom shortcuts in hotkeys.json;
//   CycleTaskSwitcher    — cyclic "next / previous" and jumping straight to a task;
//   PanelCardPresenter   — transition card (non-activating panel);
//   HotkeySettingsSection — settings section with the hotkey recorder component.

@MainActor
enum SwitchModule {
    /// Shared hotkey assignments: used by the registrar, the switcher and settings.
    static let preferences = HotkeyPreferences(store: HotkeyOverridesStore())

    static func makeCardPresenter() -> TransitionCardPresenting {
        PanelCardPresenter()
    }

    /// Current "add or remove current window" shortcut (⌃⌥⇥ by default) for hints and cards.
    static func bindHotkey() -> Hotkey? {
        preferences.assignments[.bindCurrentChat]
    }

    static func makeSwitcher(model: AppModel, bind: BindServices, card: TransitionCardPresenting) -> TaskSwitching {
        CycleTaskSwitcher(model: model, bind: bind, card: card, bindHotkey: bindHotkey)
    }

    static func makeDoneToggler(model: AppModel, bind: BindServices, card: TransitionCardPresenting) -> DoneToggling {
        LiveDoneToggler(model: model, bind: bind, card: card)
    }

    static func makeHotkeys() -> HotkeyRegistering {
        CarbonHotkeyCenter(preferences: preferences)
    }

    /// Hotkeys section for the settings window (UI embeds it as is).
    static func hotkeySettingsView(environment: AppEnvironment) -> AnyView {
        let center = environment.hotkeys as? CarbonHotkeyCenter
        return AnyView(HotkeySettingsSection(preferences: center?.preferences ?? preferences, center: center))
    }

    /// Self-test: no on-screen windows and no permission prompts.
    static func selfTest() -> [SelfTestResult] {
        SwitchSelfTest.run()
    }
}

@MainActor
private enum SwitchSelfTest {
    static func run() -> [SelfTestResult] {
        // NSPanel and NSHostingView require NSApplication; running the event loop is not needed.
        _ = NSApplication.shared
        var results: [SelfTestResult] = []
        results.append(constants())
        results.append(keyboard())
        results += card()
        results += hotkeys()
        results.append(switching())
        return results
    }

    private static func constants() -> SelfTestResult {
        let ok = HotkeyModifiers.CarbonMask.command == UInt32(cmdKey)
            && HotkeyModifiers.CarbonMask.shift == UInt32(shiftKey)
            && HotkeyModifiers.CarbonMask.option == UInt32(optionKey)
            && HotkeyModifiers.CarbonMask.control == UInt32(controlKey)
            && KeyCode.isoSection == UInt32(kVK_ISO_Section)
            && KeyCode.ansiGrave == UInt32(kVK_ANSI_Grave)
            && KeyCode.escape == UInt32(kVK_Escape)
        return SelfTestResult("SWITCH: константы Carbon совпадают с JugglerCore", passed: ok)
    }

    private static func keyboard() -> SelfTestResult {
        let raw = KeyboardDetector.layoutType()
        let kind = KeyboardDetector.current()
        let next = HotkeyAssignments.defaults(for: kind)[.nextTask]?.displayString ?? "—"
        return SelfTestResult(
            "SWITCH: тип клавиатуры определён",
            passed: raw != nil,
            detail: "\(kind.rawValue.uppercased()), «следующая» по умолчанию \(next)")
    }

    private static func card() -> [SelfTestResult] {
        let presenter = PanelCardPresenter()
        let panel = presenter.panel
        let problems = panel.flagProblems
        let content = TransitionCardContent(
            number: 2, title: "Проверка карточки", note: "Заметка", absenceText: "не был 5 мин",
            staleness: .fresh, source: nil, hint: TransitionCardBuilder.unboundHint(bindHotkey: nil))
        let size = presenter.layout(.task(content))
        let timing = presenter.timing
        return [
            SelfTestResult(
                "SWITCH: панель карточки с нужными флагами",
                passed: problems.isEmpty,
                detail: problems.isEmpty ? "уровень \(panel.level.rawValue)" : problems.joined(separator: ", ")),
            SelfTestResult(
                "SWITCH: карточка размечается без показа",
                passed: size.width > 100 && size.height > 40 && !panel.isVisible,
                detail: "\(Int(size.width))×\(Int(size.height))"),
            SelfTestResult(
                "SWITCH: карточка видна 1–1,5 с",
                passed: (1.0...1.5).contains(timing.total),
                detail: String(format: "%.2f с", timing.total)),
        ]
    }

    private static func hotkeys() -> [SelfTestResult] {
        // Separate in-memory assignments (hotkeys.json is left alone) and a dedicated signature.
        let preferences = HotkeyPreferences(store: nil)
        let center = CarbonHotkeyCenter(preferences: preferences, signature: CarbonHotkeyCenter.testSignature)
        center.start { _ in }
        let errors = preferences.registrationErrors
        let registered = center.registeredActions
        let expected = Set(HotkeyAction.allCases)
        let installedHandler = center.hasEventHandler
        let shown = HotkeyAction.allCases.compactMap { preferences.assignments[$0]?.displayString }.joined(separator: " ")

        // Re-registration when an assignment changes.
        let custom = Hotkey(keyCode: 0x5A, modifiers: [.control, .option, .shift, .command]) // ⌃⌥⇧⌘F20
        let assignError = preferences.assign(custom, to: .bindCurrentChat)
        let reRegistered = center.registeredActions == expected && preferences.registrationErrors.isEmpty

        center.stop()
        let cleanedUp = center.registeredActions.isEmpty && !center.hasEventHandler && !center.isStarted
        return [
            SelfTestResult(
                "SWITCH: хоткеи регистрируются (Carbon)",
                passed: errors.isEmpty && registered == expected && installedHandler,
                detail: errors.isEmpty
                    ? "\(shown); зарегистрировано \(registered.count) из \(expected.count), обработчик событий: \(installedHandler ? "есть" : "нет")"
                    : errors.map { "\($0.key.rawValue): \($0.value)" }.joined(separator: ", ")),
            SelfTestResult(
                "SWITCH: хоткеи перерегистрируются при смене",
                passed: assignError == nil && reRegistered),
            SelfTestResult("SWITCH: хоткеи сняты после остановки", passed: cleanedUp),
        ]
    }

    /// Switcher on a temporary store with fake BIND and card.
    private static func switching() -> SelfTestResult {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("juggler-switch-self-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = AppModel(store: TaskStore(fileURL: dir.appendingPathComponent("tasks.json")))
        let b1 = TaskBinding.appWindow(AppWindowRef(bundleID: "com.example.one", windowTitle: "Один"))
        let b2 = TaskBinding.appWindow(AppWindowRef(bundleID: "com.example.two", windowTitle: "Два"))
        let t1 = JugglerTask(title: "Первая", binding: b1)
        let t2 = JugglerTask(title: "Вторая", isDone: true, binding: b2)
        let t3 = JugglerTask(title: "Третья")
        model.update { $0.tasks = [t1, t2, t3] }

        let fake = FakeBind(context: FrontmostContext(bundleID: "com.example.one", windowTitle: "Один"))
        let card = RecordingCard()
        let switcher = CycleTaskSwitcher(
            model: model, bind: fake.services, card: card,
            bindHotkey: { Hotkey(keyCode: KeyCode.tab, modifiers: [.control, .option]) },
            beep: {})
        switcher.switchTask(.next)
        let first = card.shown.last
        let ok1 = first?.number == 3 && first?.hint?.contains("⌃⌥⇥") == true
            && model.document.lastActiveTaskID == t3.id && model.document.task(withID: t3.id)?.lastVisitedAt != nil
            && fake.activator.activated.isEmpty

        fake.provider.context = FrontmostContext(bundleID: "com.unknown")
        switcher.switchTask(.next) // current is the last active one (3) → 1, "done" (2) is skipped
        let second = card.shown.last
        let ok2 = second?.number == 1 && second?.hint == nil && fake.activator.activated == [b1]
            && model.document.lastActiveTaskID == t1.id

        return SelfTestResult(
            "SWITCH: переключение по кругу активирует привязку и отмечает заход",
            passed: ok1 && ok2,
            detail: "карточки: \(card.shown.map { "\($0.number)" }.joined(separator: "→"))")
    }
}

// MARK: - Fakes for the self-test

@MainActor
private final class RecordingCard: TransitionCardPresenting {
    var shown: [TransitionCardContent] = []
    func show(_ content: TransitionCardContent) { shown.append(content) }
}

@MainActor
private final class FakeBind {
    final class Provider: FrontmostContextProviding {
        var context: FrontmostContext
        init(_ context: FrontmostContext) { self.context = context }
        func currentContext() -> FrontmostContext { context }
    }

    final class Capturer: BindingCapturing {
        func captureBinding(from context: FrontmostContext) -> BindingCaptureResult { .failed("самопроверка") }
    }

    final class Activator: BindingActivating {
        var activated: [TaskBinding] = []
        func activate(_ binding: TaskBinding) -> ActivationResult {
            activated.append(binding)
            return .activated
        }
    }

    final class Permissions: PermissionsProviding {
        var isAccessibilityTrusted: Bool { false }
        func requestAccessibility() {}
    }

    let provider: Provider
    let activator = Activator()
    let services: BindServices

    init(context: FrontmostContext) {
        provider = Provider(context)
        services = BindServices(contextProvider: provider, capturer: Capturer(), activator: activator, permissions: Permissions())
    }
}
