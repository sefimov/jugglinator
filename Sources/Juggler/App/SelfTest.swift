import AppKit
import Foundation
import JugglerCore

/// `Juggler --self-test`: инициализирует компоненты, не запрашивая разрешений
/// и не показывая окон. Код выхода 0 — всё прошло.
///
/// Каждый модуль добавляет свои проверки в `<Module>.selfTest()` в своей папке.
@MainActor
enum SelfTest {
    static func run() -> Int32 {
        // Компонентам AppKit (панель карточки, NSHostingView) нужен NSApplication;
        // цикл событий не запускается, окна не показываются.
        _ = NSApplication.shared
        var results = coreResults()
        results += compositionResults()
        results += bundleResults()
        results += BindModule.selfTest()
        results += SwitchModule.selfTest()
        results += UIModule.selfTest()

        for result in results {
            let mark = result.passed ? "ok  " : "FAIL"
            let detail = result.detail.isEmpty ? "" : " — \(result.detail)"
            print("[\(mark)] \(result.name)\(detail)")
        }
        let failed = results.filter { !$0.passed }.count
        print("Самопроверка: \(results.count - failed) из \(results.count) прошли")
        return failed == 0 ? 0 : 1
    }

    /// Хранилище и корень композиции на временном файле (настоящий tasks.json не трогается).
    private static func coreResults() -> [SelfTestResult] {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("juggler-self-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskStore(fileURL: dir.appendingPathComponent("tasks.json"))

        var results: [SelfTestResult] = []
        do {
            let task = JugglerTask(title: "Самопроверка")
            try store.save(TasksDocument(tasks: [task], lastActiveTaskID: task.id))
            let loaded = store.load()
            results.append(SelfTestResult(
                "Хранилище: запись и чтение",
                passed: loaded.outcome == .loaded && loaded.document.tasks.map(\.id) == [task.id]))
        } catch {
            results.append(SelfTestResult("Хранилище: запись и чтение", passed: false, detail: error.localizedDescription))
        }

        let env = AppEnvironment.makeLive(store: store)
        results.append(SelfTestResult(
            "Корень композиции собирается",
            passed: env.model.tasks.count == 1 && env.model.currentTaskNumber == 1))
        // Рабочая сборка берёт настоящие реализации UI, SWITCH и BIND, а не заглушки.
        let live: [(String, Bool)] = [
            ("BIND: контекст", env.bind.contextProvider is LiveFrontmostContextProvider),
            ("BIND: активация", env.bind.activator is LiveBindingActivator),
            ("BIND: разрешения", env.bind.permissions is LivePermissions),
            ("BIND: «Сделать задачей текущий чат»", env.binder is LiveCurrentChatBinder),
            ("SWITCH: карточка", env.card is PanelCardPresenter),
            ("SWITCH: переключатель", env.switcher is CycleTaskSwitcher),
            ("SWITCH: хоткеи Carbon", env.hotkeys is CarbonHotkeyCenter),
        ]
        let missing = live.filter { !$0.1 }.map(\.0)
        results.append(SelfTestResult(
            "Корень композиции: рабочие реализации модулей",
            passed: missing.isEmpty && !env.isStarted,
            detail: missing.isEmpty ? "\(live.count) компонентов, хоткеи не запущены" : "заглушки: \(missing.joined(separator: ", "))"))
        return results
    }

    /// Связка `AppEnvironment.perform`: хоткеи и меню → переключатель SWITCH и сценарий BIND.
    /// Настоящий переключатель SWITCH работает над временным хранилищем с поддельными
    /// контекстом окна, активацией и карточкой: ни AppleScript, ни Accessibility не вызываются.
    private static func compositionResults() -> [SelfTestResult] {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("juggler-wiring-self-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = AppModel(store: TaskStore(fileURL: dir.appendingPathComponent("tasks.json")))
        let b1 = TaskBinding.appWindow(AppWindowRef(bundleID: "com.example.one", windowTitle: "Один"))
        let b2 = TaskBinding.chatGPTThread(ChatGPTThreadRef(threadID: "th-2", title: "Два"))
        let t1 = JugglerTask(title: "Первая", binding: b1)
        let t2 = JugglerTask(title: "Вторая", binding: b2)
        model.update { $0.tasks = [t1, t2] }

        let fake = WiringFakes(context: FrontmostContext(bundleID: "com.example.one", windowTitle: "Один"))
        let switcher = SwitchModule.makeSwitcher(model: model, bind: fake.services, card: fake.card)
        let env = AppEnvironment(model: model, bind: fake.services, binder: fake.binder,
                                 card: fake.card, switcher: switcher, hotkeys: fake.hotkeys)
        env.start()
        let started = env.isStarted && fake.hotkeys.handler != nil

        // ⌃§ — следующая: передняя — задача 1 → задача 2.
        fake.hotkeys.press(.nextTask)
        let nextOK = fake.card.shown.last?.number == 2 && fake.activator.activated == [b2]
            && model.document.lastActiveTaskID == t2.id
        // ⌃⇧§ — предыдущая: ChatGPT (com.openai.codex) с тем же тредом → задача 1.
        fake.provider.context = FrontmostContext(bundleID: KnownBundleIDs.chatGPT, windowTitle: "Два", chatGPTThreadID: "th-2")
        fake.hotkeys.press(.previousTask)
        let prevOK = fake.card.shown.last?.number == 1 && fake.activator.activated == [b2, b1]
            && model.document.lastActiveTaskID == t1.id
        // ⌃⌥§ — добавить или удалить текущее окно.
        fake.hotkeys.press(.bindCurrentChat)
        let bindOK = fake.binder.toggles == 1 && fake.binder.calls == 0
        env.stop()
        let stopped = !env.isStarted && fake.hotkeys.stopped

        return [
            SelfTestResult("Связка: хоткеи запускаются из корня композиции", passed: started && stopped),
            SelfTestResult("Связка: «следующая» и «предыдущая» → переключатель, карточка, привязка",
                           passed: nextOK && prevOK,
                           detail: "карточки: \(fake.card.shown.map { "\($0.number)" }.joined(separator: "→"))"),
            SelfTestResult("Связка: ⌃⌥ → «добавить или удалить текущее окно»", passed: bindOK),
            toggleResult(),
        ]
    }

    /// ⌃⌥§ как переключатель (D15) на временном хранилище: сценарий BIND с поддельным контекстом
    /// удаляет задачу переднего окна с карточкой и возвращает её повторным нажатием.
    private static func toggleResult() -> SelfTestResult {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("juggler-toggle-self-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskStore(fileURL: dir.appendingPathComponent("tasks.json"))
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var now = t0
        let model = AppModel(store: store, clock: { now })
        let b2 = TaskBinding.chatGPTThread(ChatGPTThreadRef(threadID: "th-2", title: "Два"))
        let t1 = JugglerTask(title: "Первая", createdAt: t0, binding: .appWindow(AppWindowRef(bundleID: "com.example.one", windowTitle: "Один")))
        let t2 = JugglerTask(title: "Вторая", note: "дальше", isDone: true, lastVisitedAt: t0, createdAt: t0, binding: b2)
        let t3 = JugglerTask(title: "Третья", createdAt: t0)
        model.update { $0.tasks = [t1, t2, t3]; $0.lastActiveTaskID = t2.id }
        let before = model.document

        let fake = WiringFakes(context: FrontmostContext(bundleID: KnownBundleIDs.chatGPT, windowTitle: "Два - ChatGPT"))
        let hotkey = Hotkey(keyCode: KeyCode.isoSection, modifiers: [.control, .option])
        let binder = BindModule.makeCurrentChatBinder(model: model, services: fake.services, card: fake.card, toggleHotkey: { hotkey })

        binder.toggleCurrentChat()
        let removedText = fake.card.messages.last ?? ""
        let removedOK = model.document.tasks.map(\.id) == [t1.id, t3.id]
            && store.load().document.tasks.map(\.id) == [t1.id, t3.id]
            && removedText == "Задача 2 «Вторая» удалена — ⌃⌥§ в течение 5 с вернёт"
            && fake.card.durations.last == TaskRemoval.undoWindow

        now = t0.addingTimeInterval(3)
        fake.provider.context = FrontmostContext(bundleID: "com.unknown")
        binder.toggleCurrentChat()
        let restoredOK = model.document == before && store.load().document == before
            && fake.card.messages.last == "Задача 2 «Вторая» возвращена" && model.lastRemoved == nil

        // Пункт меню «Добавить/Удалить текущее окно»: окно уже задача — удаляет её с той же карточкой.
        fake.provider.context = FrontmostContext(bundleID: KnownBundleIDs.chatGPT, windowTitle: "Два - ChatGPT")
        binder.toggleCurrentWindow()
        let menuRemovedOK = model.document.tasks.map(\.id) == [t1.id, t3.id]
            && fake.card.messages.last == "Задача 2 «Вторая» удалена — ⌃⌥§ в течение 5 с вернёт"
            && model.lastRemoved?.undoableByToggle == true

        return SelfTestResult(
            "Связка: ⌃⌥§ удаляет задачу переднего окна и возвращает её повтором в 5 с; пункт меню удаляет так же",
            passed: removedOK && restoredOK && menuRemovedOK,
            detail: removedText)
    }

    /// Проверки собранного .app (только при запуске из build/Juggler.app).
    private static func bundleResults() -> [SelfTestResult] {
        let bundle = Bundle.main
        guard bundle.bundleURL.pathExtension == "app" else {
            return [SelfTestResult("Пакет .app", passed: true, detail: "запуск не из .app — пропущено")]
        }
        let info = bundle.infoDictionary ?? [:]
        var problems: [String] = []
        if bundle.bundleIdentifier != JugglerLog.subsystem { problems.append("bundle id \(bundle.bundleIdentifier ?? "нет")") }
        if (info["LSUIElement"] as? Bool) != true { problems.append("нет LSUIElement") }
        if (info["LSMinimumSystemVersion"] as? String) != "14.0" { problems.append("LSMinimumSystemVersion не 14.0") }
        let appleEvents = bundle.object(forInfoDictionaryKey: "NSAppleEventsUsageDescription") as? String ?? ""
        if appleEvents.range(of: "\\p{Cyrillic}", options: .regularExpression) == nil {
            problems.append("NSAppleEventsUsageDescription не на русском")
        }
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return [SelfTestResult(
            "Пакет .app: Info.plist",
            passed: problems.isEmpty,
            detail: problems.isEmpty ? "\(bundle.bundleIdentifier ?? "") \(version) (\(build)), локализация \(bundle.preferredLocalizations.first ?? "?")"
                                     : problems.joined(separator: ", "))]
    }
}

// MARK: - Подделки для проверки связки

@MainActor
private final class WiringFakes {
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

    final class Card: TransitionCardPresenting, TransitionMessagePresenting {
        var shown: [TransitionCardContent] = []
        var messages: [String] = []
        var durations: [TimeInterval?] = []
        func show(_ content: TransitionCardContent) { shown.append(content) }
        func showMessage(_ text: String) { messages.append(text); durations.append(nil) }
        func showMessage(_ text: String, duration: TimeInterval) { messages.append(text); durations.append(duration) }
    }

    final class Binder: CurrentChatBinding {
        var calls = 0
        var toggles = 0
        var menuToggles = 0
        func bindCurrentChat() { calls += 1 }
        func toggleCurrentChat() { toggles += 1 }
        func toggleCurrentWindow() { menuToggles += 1 }
    }

    final class Hotkeys: HotkeyRegistering {
        var handler: ((HotkeyAction) -> Void)?
        var stopped = false
        func start(handler: @escaping (HotkeyAction) -> Void) { self.handler = handler }
        func stop() { handler = nil; stopped = true }
        func press(_ action: HotkeyAction) { handler?(action) }
    }

    let provider: Provider
    let activator = Activator()
    let card = Card()
    let binder = Binder()
    let hotkeys = Hotkeys()
    let services: BindServices

    init(context: FrontmostContext) {
        provider = Provider(context)
        services = BindServices(contextProvider: provider, capturer: Capturer(), activator: activator, permissions: Permissions())
    }
}
