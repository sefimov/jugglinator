import AppKit
import Carbon
import Foundation
import JugglerCore
import SwiftUI

// Папка Sources/Juggler/Switch/ принадлежит задаче SWITCH.
// Сигнатуры функций `SwitchModule` — контракт с корнем композиции (App/CompositionRoot.swift),
// UI (раздел хоткеев в настройках) и самопроверкой (App/SelfTest.swift).
//
// Состав:
//   CarbonHotkeyCenter   — глобальные хоткеи (Carbon), перерегистрация при смене назначений;
//   HotkeyPreferences    — умолчания по типу клавиатуры + свои сочетания в hotkeys.json;
//   CycleTaskSwitcher    — «следующая / предыдущая» по кругу и прямой переход к задаче;
//   PanelCardPresenter   — карточка перехода (неактивирующая панель);
//   HotkeySettingsSection — раздел настроек с компонентом записи хоткея.

@MainActor
enum SwitchModule {
    /// Общие назначения хоткеев: их разделяют регистратор, переключатель и настройки.
    static let preferences = HotkeyPreferences(store: HotkeyOverridesStore())

    static func makeCardPresenter() -> TransitionCardPresenting {
        PanelCardPresenter()
    }

    static func makeSwitcher(model: AppModel, bind: BindServices, card: TransitionCardPresenting) -> TaskSwitching {
        let preferences = self.preferences
        return CycleTaskSwitcher(model: model, bind: bind, card: card) {
            preferences.assignments[.bindCurrentChat]
        }
    }

    static func makeHotkeys() -> HotkeyRegistering {
        CarbonHotkeyCenter(preferences: preferences)
    }

    /// Раздел хоткеев для окна настроек (UI встраивает его как есть).
    static func hotkeySettingsView(environment: AppEnvironment) -> AnyView {
        let center = environment.hotkeys as? CarbonHotkeyCenter
        return AnyView(HotkeySettingsSection(preferences: center?.preferences ?? preferences, center: center))
    }

    /// Самопроверка: без окон на экране и без запросов разрешений.
    static func selfTest() -> [SelfTestResult] {
        SwitchSelfTest.run()
    }
}

@MainActor
private enum SwitchSelfTest {
    static func run() -> [SelfTestResult] {
        // NSPanel и NSHostingView требуют NSApplication; запуск цикла событий не нужен.
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
        // Отдельные назначения в памяти (hotkeys.json не трогаем) и своя подпись.
        let preferences = HotkeyPreferences(store: nil)
        let center = CarbonHotkeyCenter(preferences: preferences, signature: CarbonHotkeyCenter.testSignature)
        center.start { _ in }
        let errors = preferences.registrationErrors
        let registered = center.registeredActions
        let expected = Set(HotkeyAction.allCases)
        let installedHandler = center.hasEventHandler
        let shown = HotkeyAction.allCases.compactMap { preferences.assignments[$0]?.displayString }.joined(separator: " ")

        // Перерегистрация при смене назначения.
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

    /// Переключатель на временном хранилище с поддельными BIND и карточкой.
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
            bindHotkey: { Hotkey(keyCode: KeyCode.isoSection, modifiers: [.control, .option]) },
            beep: {})
        switcher.switchTask(.next)
        let first = card.shown.last
        let ok1 = first?.number == 3 && first?.hint?.contains("⌃⌥§") == true
            && model.document.lastActiveTaskID == t3.id && model.document.task(withID: t3.id)?.lastVisitedAt != nil
            && fake.activator.activated.isEmpty

        fake.provider.context = FrontmostContext(bundleID: "com.unknown")
        switcher.switchTask(.next) // текущая — последняя активная (3) → 1, «сделано» (2) пропущена
        let second = card.shown.last
        let ok2 = second?.number == 1 && second?.hint == nil && fake.activator.activated == [b1]
            && model.document.lastActiveTaskID == t1.id

        return SelfTestResult(
            "SWITCH: переключение по кругу активирует привязку и отмечает заход",
            passed: ok1 && ok2,
            detail: "карточки: \(card.shown.map { "\($0.number)" }.joined(separator: "→"))")
    }
}

// MARK: - Подделки для самопроверки

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
