import AppKit
import Foundation
import JugglerCore

/// `Juggler --self-test`: initializes components without requesting permissions
/// or showing windows. Exit code 0 — everything passed.
///
/// Each module adds its checks to `<Module>.selfTest()` in its own folder.
@MainActor
enum SelfTest {
    static func run() -> Int32 {
        // AppKit components (card panel, NSHostingView) need NSApplication;
        // the event loop isn't started, no windows are shown.
        _ = NSApplication.shared
        var results = coreResults()
        results += compositionResults()
        results += bundleResults()
        results += BindModule.selfTest()
        results += SwitchModule.selfTest()
        results += UIModule.selfTest()
        results += MCPModule.selfTest()

        for result in results {
            let mark = result.passed ? "ok  " : "FAIL"
            let detail = result.detail.isEmpty ? "" : " — \(result.detail)"
            print("[\(mark)] \(result.name)\(detail)")
        }
        let failed = results.filter { !$0.passed }.count
        print("Самопроверка: \(results.count - failed) из \(results.count) прошли")
        return failed == 0 ? 0 : 1
    }

    /// Store and composition root on a temporary file (the real tasks.json is untouched).
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
        // The production build uses the real UI, SWITCH and BIND implementations, not stubs.
        let live: [(String, Bool)] = [
            ("BIND: контекст", env.bind.contextProvider is LiveFrontmostContextProvider),
            ("BIND: активация", env.bind.activator is LiveBindingActivator),
            ("BIND: разрешения", env.bind.permissions is LivePermissions),
            ("BIND: «Сделать задачей текущий чат»", env.binder is LiveCurrentChatBinder),
            ("SWITCH: карточка", env.card is PanelCardPresenter),
            ("SWITCH: переключатель", env.switcher is CycleTaskSwitcher),
            ("SWITCH: «сделано» ⌃§", env.doneToggler is LiveDoneToggler),
            ("SWITCH: хоткеи Carbon", env.hotkeys is CarbonHotkeyCenter),
            ("MCP: сервер", env.mcp != nil),
        ]
        let missing = live.filter { !$0.1 }.map(\.0)
        results.append(SelfTestResult(
            "Корень композиции: рабочие реализации модулей",
            passed: missing.isEmpty && !env.isStarted && env.mcp?.isListening == false,
            detail: missing.isEmpty ? "\(live.count) компонентов, хоткеи и MCP не запущены" : "заглушки: \(missing.joined(separator: ", "))"))
        return results
    }

    /// `AppEnvironment.perform` wiring: hotkeys and menu → SWITCH switcher and BIND flow.
    /// The real SWITCH switcher runs over a temporary store with fake
    /// window context, activation and card: neither AppleScript nor Accessibility is called.
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
        let doneToggler = SwitchModule.makeDoneToggler(model: model, bind: fake.services, card: fake.card,
                                                       addWithDialogs: { fake.binder.bindCurrentChat() })
        let env = AppEnvironment(model: model, bind: fake.services, binder: fake.binder,
                                 card: fake.card, switcher: switcher, doneToggler: doneToggler, hotkeys: fake.hotkeys)
        env.start()
        let started = env.isStarted && fake.hotkeys.handler != nil

        // ⌃⇥ — next: frontmost is task 1 → task 2.
        fake.hotkeys.press(.nextTask)
        let nextOK = fake.card.shown.last?.number == 2 && fake.activator.activated == [b2]
            && model.document.lastActiveTaskID == t2.id
        // ⌃⇧⇥ — previous: ChatGPT (com.openai.codex) with the same thread → task 1.
        fake.provider.context = FrontmostContext(bundleID: KnownBundleIDs.chatGPT, windowTitle: "Два", chatGPTThreadID: "th-2")
        fake.hotkeys.press(.previousTask)
        let prevOK = fake.card.shown.last?.number == 1 && fake.activator.activated == [b2, b1]
            && model.document.lastActiveTaskID == t1.id
        // ⌃⌥⇥ — add or remove the current window.
        fake.hotkeys.press(.bindCurrentChat)
        let bindOK = fake.binder.toggles == 1 && fake.binder.calls == 0
        // ⌃§ — "done": frontmost is task 1 (exact match), windows don't switch; repeating clears it.
        fake.provider.context = FrontmostContext(bundleID: "com.example.one", windowTitle: "Один")
        let activations = fake.activator.activated.count
        let shownCards = fake.card.shown.count
        fake.hotkeys.press(.toggleDone)
        let doneOn = model.document.task(withID: t1.id)?.isDone == true
            && fake.card.messages.last == DoneToggleTexts.card(number: 1, title: "Первая", isDone: true)
        fake.hotkeys.press(.toggleDone)
        let doneOff = model.document.task(withID: t1.id)?.isDone == false
            && fake.card.messages.last == DoneToggleTexts.card(number: 1, title: "Первая", isDone: false)
        let doneOK = doneOn && doneOff && fake.activator.activated.count == activations && fake.card.shown.count == shownCards
        // ⌃§ in a window that is not a task: the window becomes task 3, the current task 1 is not marked.
        fake.provider.context = FrontmostContext(bundleID: "com.example.new", windowTitle: "Новое")
        fake.hotkeys.press(.toggleDone)
        let added = model.document.tasks.count == 3 && model.document.tasks[2].title == "Новое"
            && model.document.tasks.allSatisfy { !$0.isDone }
            && fake.card.messages.last == TaskToggleTexts.addedCard(number: 3, title: "Новое")
        // ⌃§ where nothing can be added (capture fails): only a sound and a card, nothing marked or added.
        fake.provider.context = FrontmostContext(bundleID: "com.example.zzz", windowTitle: "Чужое")
        fake.hotkeys.press(.toggleDone)
        let untouched = model.document.tasks.count == 3 && model.document.tasks.allSatisfy { !$0.isDone }
            && fake.card.messages.last == "самопроверка"
        // ⌃⇥ in a window that is not a task: nothing is added, it switches to a task window.
        fake.provider.context = FrontmostContext(bundleID: "com.example.new", windowTitle: "Ещё")
        let shownBefore = fake.card.shown.count
        fake.hotkeys.press(.nextTask)
        let switchedOnly = model.document.tasks.count == 3 && fake.card.shown.count == shownBefore + 1
            && fake.activator.activated.count == activations + 1
        let addOK = added && untouched && switchedOnly && fake.binder.calls == 0
        env.stop()
        let stopped = !env.isStarted && fake.hotkeys.stopped

        return [
            SelfTestResult("Связка: хоткеи запускаются из корня композиции", passed: started && stopped),
            SelfTestResult("Связка: «следующая» и «предыдущая» → переключатель, карточка, привязка",
                           passed: nextOK && prevOK,
                           detail: "карточки: \(fake.card.shown.map { "\($0.number)" }.joined(separator: "→"))"),
            SelfTestResult("Связка: ⌃⌥ → «добавить или удалить текущее окно»", passed: bindOK),
            SelfTestResult("Связка: ⌃§ → «сделано» и обратно, без переключения окон", passed: doneOK),
            SelfTestResult("Связка: ⌃§ в окне не из списка добавляет его, ⌃⇥ — переключает, текущую задачу не трогают", passed: addOK),
            toggleResult(),
            clearAllResult(),
        ]
    }

    /// ⌃⌥⇥ as a toggle (D15) on a temporary store: the BIND flow with a fake context
    /// removes the frontmost window's task with a card and restores it on a repeat press.
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
        let hotkey = Hotkey(keyCode: KeyCode.tab, modifiers: [.control, .option])
        let binder = BindModule.makeCurrentChatBinder(model: model, services: fake.services, card: fake.card, toggleHotkey: { hotkey })

        binder.toggleCurrentChat()
        let removedText = fake.card.messages.last ?? ""
        let removedOK = model.document.tasks.map(\.id) == [t1.id, t3.id]
            && store.load().document.tasks.map(\.id) == [t1.id, t3.id]
            && removedText == TaskToggleTexts.removedCard(number: 2, title: "Вторая", hotkey: hotkey)
            && fake.card.durations.last == TaskRemoval.undoWindow

        now = t0.addingTimeInterval(3)
        fake.provider.context = FrontmostContext(bundleID: "com.unknown")
        binder.toggleCurrentChat()
        let restoredOK = model.document == before && store.load().document == before
            && fake.card.messages.last == TaskToggleTexts.restoredCard(number: 2, title: "Вторая") && model.lastRemoved == nil

        // "Add/Remove current window" menu item: the window is already a task — removes it with the same card.
        fake.provider.context = FrontmostContext(bundleID: KnownBundleIDs.chatGPT, windowTitle: "Два - ChatGPT")
        binder.toggleCurrentWindow()
        let menuRemovedOK = model.document.tasks.map(\.id) == [t1.id, t3.id]
            && fake.card.messages.last == TaskToggleTexts.removedCard(number: 2, title: "Вторая", hotkey: hotkey)
            && model.lastRemoved?.undoableByToggle == true

        // A window that is not a task yet: added to the end of the list with a card.
        fake.provider.context = FrontmostContext(bundleID: "com.example.new", windowTitle: "Новое")
        binder.toggleCurrentWindow()
        let addedOK = model.document.tasks.count == 3 && model.document.tasks.last?.title == "Новое"
            && fake.card.messages.last == TaskToggleTexts.addedCard(number: 3, title: "Новое")

        return SelfTestResult(
            "Связка: ⌃⌥⇥ удаляет задачу переднего окна и возвращает её повтором в 5 с; пункт меню удаляет так же; новое окно добавляется с карточкой",
            passed: removedOK && restoredOK && menuRemovedOK && addedOK,
            detail: removedText)
    }

    /// "Clear all tasks" on a temporary store: the list is empty and saved, the current task is cleared,
    /// "Restore removed task" restores nothing after the clear.
    private static func clearAllResult() -> SelfTestResult {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("juggler-clear-self-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskStore(fileURL: dir.appendingPathComponent("tasks.json"))
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let model = AppModel(store: store, clock: { t0 })
        let t1 = JugglerTask(title: "Первая", createdAt: t0)
        let t2 = JugglerTask(title: "Вторая", createdAt: t0)
        let t3 = JugglerTask(title: "Третья", createdAt: t0)
        model.update { $0.tasks = [t1, t2, t3]; $0.lastActiveTaskID = t2.id }
        model.removeTask(t3.id, undoableByToggle: false)
        let hadRemoved = model.lastRemoved != nil

        let count = model.clearAllTasks()
        let saved = store.load().document
        let clearedOK = count == 2 && model.document.tasks.isEmpty && model.document.lastActiveTaskID == nil
            && saved.tasks.isEmpty && saved.lastActiveTaskID == nil
        let noRestoreOK = hadRemoved && model.lastRemoved == nil && model.restoreLastRemoved() == nil && model.document.tasks.isEmpty

        return SelfTestResult(
            "Очистка списка: задачи удалены и сохранены, текущая снята, возврата очищенных нет",
            passed: clearedOK && noRestoreOK,
            detail: "удалено \(count)")
    }

    /// Checks of the built .app (only when launched from build/Juggler.app).
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
        if (info["NSAppleEventsUsageDescription"] as? String ?? "").isEmpty { problems.append("нет NSAppleEventsUsageDescription") }
        let declared = info["CFBundleLocalizations"] as? [String] ?? []
        let missing = declared.filter { bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: $0) == nil }
        if declared.isEmpty || !missing.isEmpty { problems.append("нет переводов: \(missing.isEmpty ? "CFBundleLocalizations" : missing.joined(separator: ", "))") }
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return [SelfTestResult(
            "Пакет .app: Info.plist",
            passed: problems.isEmpty,
            detail: problems.isEmpty ? "\(bundle.bundleIdentifier ?? "") \(version) (\(build)), языков \(declared.count), выбран \(bundle.preferredLocalizations.first ?? "?")"
                                     : problems.joined(separator: ", "))]
    }
}

// MARK: - Fakes for the wiring check

@MainActor
private final class WiringFakes {
    final class Provider: FrontmostContextProviding {
        var context: FrontmostContext
        init(_ context: FrontmostContext) { self.context = context }
        func currentContext() -> FrontmostContext { context }
    }

    final class Capturer: BindingCapturing {
        func captureBinding(from context: FrontmostContext) -> BindingCaptureResult {
            guard context.bundleID == "com.example.new" else { return .failed("самопроверка") }
            return .captured(.appWindow(AppWindowRef(bundleID: "com.example.new", windowTitle: context.windowTitle ?? "")),
                             suggestedTitle: context.windowTitle ?? "")
        }
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
