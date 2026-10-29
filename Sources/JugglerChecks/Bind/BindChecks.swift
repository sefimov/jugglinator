import Foundation
import JugglerCore

// The Sources/JugglerChecks/Bind/ folder belongs to task BIND.
// Checks for the pure logic in Sources/JugglerCore/Bind/.

enum BindChecks: CheckSuite {
    static let name = "Bind"

    static func run(_ c: CheckRunner) {
        appKinds(c)
        frontmostChooser(c)
        automationStatus(c)
        chromeOutput(c)
        chromeMatcher(c)
        claudeExtractor(c)
        windowTitles(c)
        capture(c)
        manualLinks(c)
        planner(c)
        probe(c)
        sessions(c)
        chatGPTThreads(c)
        terminal(c)
    }

    static let uuid = "0f8fad5b-d9cb-469f-a165-70867728950e"
    static let sep = "\u{1F}"
    static let rec = "\u{1E}"

    static func appKinds(_ c: CheckRunner) {
        c.group("Приложения") {
            c.expectEqual(BindApps.kind(of: "com.google.Chrome"), .chrome, "Chrome")
            c.expectEqual(BindApps.kind(of: "COM.GOOGLE.CHROME"), .chrome, "Chrome без учёта регистра")
            c.expectEqual(BindApps.kind(of: "com.anthropic.claudefordesktop"), .claude, "Claude")
            c.expectEqual(BindApps.kind(of: "com.openai.codex"), .chatGPT, "ChatGPT (com.openai.codex, как на маке)")
            c.expectEqual(BindApps.kind(of: "com.openai.chat"), .chatGPT, "ChatGPT (старый com.openai.chat)")
            c.expectEqual(BindApps.kind(of: "com.anysphere.sand"), .other, "Grok Bot — окно")
            c.expectEqual(BindApps.kind(of: nil), .other, "nil — прочее")
            c.expect(!BindApps.same("", ""), "пустые bundle id не равны")
        }
    }

    static func frontmostChooser(_ c: CheckRunner) {
        c.group("Переднее приложение") {
            let own = AppIdentity(bundleID: "com.sefimov.juggler", name: "Juggler", pid: 10)
            let unbundledOwn = AppIdentity(bundleID: nil, name: "Juggler", pid: 10)
            let claude = AppIdentity(bundleID: BindApps.claude, name: "Claude", pid: 20)
            let grok = AppIdentity(bundleID: BindApps.grokBot, name: "Grok Bot", pid: 30)

            let a = FrontmostAppChooser.choose(frontmost: claude, remembered: grok, ownBundleID: "com.sefimov.juggler", ownPID: 10)
            c.expectEqual(a?.app, claude, "чужое переднее приложение берётся как есть")
            c.expectEqual(a?.usedRemembered, false, "без запомненного")

            let b = FrontmostAppChooser.choose(frontmost: own, remembered: grok, ownBundleID: "com.sefimov.juggler", ownPID: 10)
            c.expectEqual(b?.app, grok, "впереди Juggler → последнее другое приложение")
            c.expectEqual(b?.usedRemembered, true, "признак запомненного")

            let d = FrontmostAppChooser.choose(frontmost: unbundledOwn, remembered: claude, ownBundleID: nil, ownPID: 10)
            c.expectEqual(d?.app, claude, "swift run (без bundle id): свой процесс узнаётся по pid")

            let e = FrontmostAppChooser.choose(
                frontmost: AppIdentity(bundleID: "com.sefimov.juggler", name: nil, pid: 99), remembered: nil, ownBundleID: nil, ownPID: 10)
            c.expectNil(e?.app, "Juggler по bundle id и нечего вспомнить → nil")
            c.expectNil(FrontmostAppChooser.choose(frontmost: nil, remembered: own, ownBundleID: nil, ownPID: 10)?.app,
                        "запомненный Juggler не берётся")
        }
    }

    static func automationStatus(_ c: CheckRunner) {
        c.group("Ошибки AppleScript") {
            c.expectEqual(AutomationStatus.classify(code: -1743), .denied, "-1743 — отказ в разрешении")
            c.expect(AutomationStatus.isPermissionDenied(code: -1743), "-1743 распознаётся как отказ")
            c.expect(!AutomationStatus.isPermissionDenied(code: -1728), "-1728 — не отказ")
            c.expectEqual(AutomationStatus.classify(code: -1744), .requiresConsent, "-1744 — нужен запрос")
            c.expectEqual(AutomationStatus.classify(code: 0), .granted, "0 — разрешено")
            c.expectEqual(AutomationStatus.classify(code: -600), .notRunning, "-600 — не запущено")
            c.expectEqual(AutomationStatus.classify(code: -1728), .noWindow, "-1728 — нет окна")
            c.expectEqual(AutomationStatus.classify(code: -2741), .failed, "прочее — ошибка")
        }
    }

    static func chromeOutput(_ c: CheckRunner) {
        c.group("Вывод AppleScript Chrome") {
            let tab = ChromeScripts.parseActiveTab("1234\(sep)987654\(sep)https://claude.ai/chat/\(uuid)\(sep)Чат - Claude")
            c.expectEqual(tab, ChromeTabRef(tabID: 987654, windowID: 1234, url: "https://claude.ai/chat/\(uuid)", title: "Чат - Claude"),
                          "активная вкладка")
            let withSep = ChromeScripts.parseActiveTab("1\(sep)2\(sep)https://x.y/\(sep)A \(sep) B")
            c.expectEqual(withSep?.title, "A \(sep) B", "разделитель в заголовке не ломает разбор")
            c.expectEqual(ChromeScripts.parseActiveTab("1\(sep)2\(sep)https://x.y/\(sep)")?.title, "", "пустой заголовок")
            c.expectNil(ChromeScripts.parseActiveTab(""), "пустой вывод — окон нет")
            c.expectNil(ChromeScripts.parseActiveTab("1\(sep)2\(sep)\(sep)T"), "без адреса — nil")
            c.expectEqual(ChromeScripts.parseActiveTab("x\(sep)y\(sep)https://a.b\(sep)T")?.tabID, nil, "нечисловые id → nil, адрес сохраняется")
            c.expectEqual(ChromeScripts.parseID(" 42.0 "), 42, "id «42.0» читается как 42")
            c.expectNil(ChromeScripts.parseID("4.5"), "дробный id — nil")

            let listing = ChromeScripts.parseTabListing(
                "1\(sep)1\(sep)11\(sep)https://a.com\(rec)1\(sep)2\(sep)12\(sep)https://b.com/x?q=1\(rec)2\(sep)1\(sep)21\(sep)chrome://newtab/\(rec)garbage\(rec)")
            c.expectEqual(listing.count, 3, "три вкладки, мусор пропущен")
            c.expectEqual(listing.last, ChromeTabEntry(windowID: 2, index: 1, tabID: 21, url: "chrome://newtab/"), "поля записи")
            c.expect(ChromeScripts.parseTabListing("").isEmpty, "пустой список")
            c.expect(ChromeScripts.activeTabSource().contains("com.google.Chrome"), "скрипт адресован Chrome по bundle id")
            c.expect(ChromeScripts.focusTabSource(windowID: 7, tabIndex: 3).contains("window id 7")
                     && ChromeScripts.focusTabSource(windowID: 7, tabIndex: 3).contains("active tab index of w to 3"),
                     "скрипт фокуса подставляет окно и вкладку")
        }
    }

    static func chromeMatcher(_ c: CheckRunner) {
        c.group("Поиск вкладки Chrome") {
            let entries = [
                ChromeTabEntry(windowID: 1, index: 1, tabID: 11, url: "https://a.com/page"),
                ChromeTabEntry(windowID: 1, index: 2, tabID: 12, url: "https://claude.ai/chat/\(uuid)"),
                ChromeTabEntry(windowID: 2, index: 1, tabID: 21, url: "https://claude.ai/chat/\(uuid)#x"),
            ]
            let byID = ChromeTabMatcher.find(ChromeTabRef(tabID: 21, windowID: 2, url: "https://other"), in: entries)
            c.expectEqual(byID?.kind, .byID, "сначала по id")
            c.expectEqual(byID?.entry.tabID, 21, "найдена вкладка с id")

            let byURL = ChromeTabMatcher.find(ChromeTabRef(tabID: 999, windowID: nil, url: "HTTPS://A.COM/page/"), in: entries)
            c.expectEqual(byURL?.kind, .byURL, "id устарел (перезапуск Chrome) → по адресу")
            c.expectEqual(byURL?.entry.tabID, 11, "адрес сравнивается нормализованным")

            let preferWindow = ChromeTabMatcher.find(ChromeTabRef(tabID: nil, windowID: 2, url: "https://claude.ai/chat/\(uuid)"), in: entries)
            c.expectEqual(preferWindow?.entry.windowID, 2, "среди одинаковых адресов — окно из привязки")
            c.expectNil(ChromeTabMatcher.find(ChromeTabRef(tabID: 5, url: "https://gone.com"), in: entries), "вкладки нет → nil")
            c.expectNil(ChromeTabMatcher.find(ChromeTabRef(tabID: nil, url: ""), in: entries), "пустой адрес не совпадает ни с чем")

            c.expectEqual(ChromeTabMatcher.reopenURL(for: ChromeTabRef(url: "https://a.com"))?.absoluteString, "https://a.com", "http(s) можно открыть заново")
            c.expectNil(ChromeTabMatcher.reopenURL(for: ChromeTabRef(url: "chrome://newtab/")), "chrome:// заново не открывается")
        }
    }

    static func claudeExtractor(_ c: CheckRunner) {
        c.group("Адрес чата Claude из Accessibility") {
            let candidates = ["file:///Applications/Claude.app/index.html", "https://claude.ai/new", "https://claude.ai/chat/\(uuid.uppercased())?x=1"]
            c.expectEqual(ClaudeChatURLExtractor.conversationID(fromCandidates: candidates), uuid, "id из адреса веб-области, в нижнем регистре")
            c.expectNil(ClaudeChatURLExtractor.conversationID(fromCandidates: ["https://claude.ai/project/\(uuid)"]), "проект — не чат")
            c.expectEqual(ClaudeChatURLExtractor.status(candidates: candidates, treeAvailable: true, accessibilityTrusted: true), .read, "статус read")
            c.expectEqual(ClaudeChatURLExtractor.status(candidates: ["https://claude.ai/new"], treeAvailable: true, accessibilityTrusted: true),
                          .notFound, "дерево есть, чата нет — notFound")
            c.expectEqual(ClaudeChatURLExtractor.status(candidates: [], treeAvailable: false, accessibilityTrusted: true),
                          .treeUnavailable, "Electron не отдал дерево")
            c.expectEqual(ClaudeChatURLExtractor.status(candidates: candidates, treeAvailable: true, accessibilityTrusted: false),
                          .noAccessibility, "без разрешения — честно noAccessibility")
        }
    }

    static func windowTitles(_ c: CheckRunner) {
        c.group("Заголовки окон") {
            let titles = ["Grok Bot", "План релиза — Grok", "  Заметки  "]
            c.expectEqual(WindowTitleMatcher.bestIndex(of: "План релиза — Grok", in: titles), 1, "точное совпадение")
            c.expectEqual(WindowTitleMatcher.bestIndex(of: "план релиза", in: titles), 1, "очищенный заголовок без учёта регистра")
            c.expectEqual(WindowTitleMatcher.bestIndex(of: "Заметки", in: titles), 2, "пробелы по краям")
            c.expectNil(WindowTitleMatcher.bestIndex(of: "", in: titles), "пустой заголовок — nil")
            c.expectNil(WindowTitleMatcher.bestIndex(of: "Другое", in: titles), "нет совпадения — nil")
        }
    }

    static func capture(_ c: CheckRunner) {
        c.group("Привязка по контексту") {
            let tab = ChromeTabRef(tabID: 5, windowID: 1, url: "https://grok.com/c/1", title: "(2) Идея - Grok")
            let chrome = BindingCapture.capture(context: FrontmostContext(bundleID: BindApps.chrome, appName: "Google Chrome", chromeTab: tab))
            c.expectEqual(chrome, .captured(.chromeTab(tab), suggestedTitle: "Идея"), "Chrome → вкладка, название очищено")

            let denied = BindingCapture.capture(context: FrontmostContext(bundleID: BindApps.chrome), chromeStatus: .denied)
            c.expectEqual(denied, .failed(BindTexts.chromeTabUnavailable(.denied)), "Chrome без разрешения → пояснение")
            if case .failed(let text) = denied { c.expect(text.contains("Автоматизация"), "в пояснении есть путь в настройки") }

            let claudeOK = BindingCapture.capture(context: FrontmostContext(
                bundleID: BindApps.claude, windowTitle: "Рефакторинг - Claude", claudeConversationID: uuid))
            c.expectEqual(claudeOK, .captured(.claudeChat(ClaudeChatRef(conversationID: uuid, title: "Рефакторинг - Claude")),
                                              suggestedTitle: "Рефакторинг"), "Claude с id → чат")
            let claudeNoID = BindingCapture.capture(context: FrontmostContext(bundleID: BindApps.claude, windowTitle: "Claude"))
            c.expectEqual(claudeNoID, .needsManualLink(.claudeChat, suggestedTitle: "Новая задача"), "Claude без id → запрос ссылки")

            let gpt = BindingCapture.capture(context: FrontmostContext(bundleID: "com.openai.codex", windowTitle: "Отчёт"))
            c.expectEqual(gpt, .needsManualLink(.chatGPTThread, suggestedTitle: "Отчёт"), "ChatGPT → запрос ссылки codex://")

            let grok = BindingCapture.capture(context: FrontmostContext(bundleID: BindApps.grokBot, appName: "Grok Bot", windowTitle: "Grok Bot"))
            c.expectEqual(grok, .captured(.appWindow(AppWindowRef(bundleID: BindApps.grokBot, windowTitle: "Grok Bot", appName: "Grok Bot")),
                                          suggestedTitle: "Grok Bot"), "Grok Bot → окно, название по имени приложения")
            let noAX = BindingCapture.capture(context: FrontmostContext(bundleID: "com.apple.Notes", appName: "Заметки"))
            c.expectEqual(noAX, .captured(.appWindow(AppWindowRef(bundleID: "com.apple.Notes", windowTitle: "", appName: "Заметки")),
                                          suggestedTitle: "Заметки"), "без Accessibility — окно без заголовка")

            c.expectEqual(BindingCapture.capture(context: FrontmostContext(bundleID: "com.sefimov.juggler")),
                          .failed(BindTexts.frontmostIsJuggler), "сам Juggler не привязывается")
            c.expectEqual(BindingCapture.capture(context: .unknown), .failed(BindTexts.noFrontmostApp), "нет контекста → ошибка")
        }
    }

    static func manualLinks(_ c: CheckRunner) {
        c.group("Вставленная ссылка") {
            c.expectEqual(BindingCapture.bindingFromManualLink(" https://claude.ai/chat/\(uuid) ", expected: .claudeChat, windowTitle: "Чат"),
                          .binding(.claudeChat(ClaudeChatRef(conversationID: uuid, title: "Чат"))), "ссылка Claude")
            c.expectEqual(BindingCapture.bindingFromManualLink("codex://threads/019a-xyz", expected: .chatGPTThread, windowTitle: nil),
                          .binding(.chatGPTThread(ChatGPTThreadRef(threadID: "019a-xyz"))), "ссылка codex://threads")
            c.expectEqual(BindingCapture.bindingFromManualLink(uuid.uppercased(), expected: .chatGPTThread, windowTitle: nil),
                          .binding(.chatGPTThread(ChatGPTThreadRef(threadID: uuid.uppercased()))), "голый UUID в ChatGPT — id треда")
            c.expectEqual(BindingCapture.bindingFromManualLink(uuid, expected: .claudeChat, windowTitle: nil),
                          .binding(.claudeChat(ClaudeChatRef(conversationID: uuid))), "голый UUID в Claude — чат")
            c.expectEqual(BindingCapture.bindingFromManualLink("https://chatgpt.com/c/1", expected: .chatGPTThread, windowTitle: nil),
                          .invalid(BindTexts.unrecognizedLink(.chatGPTThread)), "веб-ссылка ChatGPT не подходит")
            c.expectEqual(BindingCapture.bindingFromManualLink("   ", expected: .claudeChat, windowTitle: nil),
                          .invalid(BindTexts.emptyLink), "пустой ввод")
        }
    }

    static func planner(_ c: CheckRunner) {
        c.group("Сценарий «Сделать задачей текущий чат»") {
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let chat = TaskBinding.claudeChat(ClaudeChatRef(conversationID: uuid, title: "A"))
            let bound = JugglerTask(title: "Связанная", binding: chat)
            let free = JugglerTask(title: "Свободная")

            var doc = TasksDocument(tasks: [free, bound], lastActiveTaskID: free.id)
            c.expectEqual(BindPlanner.plan(document: doc, binding: .claudeChat(ClaudeChatRef(conversationID: uuid.uppercased()))),
                          .alreadyBound(taskID: bound.id, number: 2), "чат уже привязан → его задача")
            let other = TaskBinding.chatGPTThread(ChatGPTThreadRef(threadID: "t1"))
            c.expectEqual(BindPlanner.plan(document: doc, binding: other),
                          .offerAttach(taskID: free.id, number: 1, taskTitle: "Свободная"), "текущая без привязки → предложить")

            doc.lastActiveTaskID = bound.id
            c.expectEqual(BindPlanner.plan(document: doc, binding: other), .createNew, "текущая с привязкой → новая задача")
            c.expectEqual(BindPlanner.plan(document: TasksDocument(), binding: other), .createNew, "пустой список → новая задача")

            let id = BindPlanner.createTask(in: &doc, title: "  Новая  ", binding: other, now: now)
            c.expectEqual(doc.tasks.last?.title, "Новая", "название обрезано")
            c.expectEqual(doc.tasks.last?.binding, other, "привязка сохранена")
            c.expectEqual(doc.lastActiveTaskID, id, "новая задача — текущая")
            c.expectEqual(doc.tasks.last?.lastVisitedAt, now, "время захода")

            var doc2 = TasksDocument(tasks: [JugglerTask(title: " ")], lastActiveTaskID: nil)
            let tid = doc2.tasks[0].id
            c.expect(BindPlanner.attach(other, to: tid, in: &doc2, suggestedTitle: "Из чата", now: now), "привязка к задаче")
            c.expectEqual(doc2.tasks[0].title, "Из чата", "пустое название заменено")
            c.expect(!BindPlanner.attach(other, to: UUID(), in: &doc2, suggestedTitle: "", now: now), "несуществующая задача — false")

            let w1 = TaskBinding.appWindow(AppWindowRef(bundleID: BindApps.grokBot, windowTitle: "План - Grok"))
            let w2 = TaskBinding.appWindow(AppWindowRef(bundleID: "COM.ANYSPHERE.SAND", windowTitle: "план"))
            c.expect(BindPlanner.sameTarget(w1, w2), "окна: тот же bundle id и очищенный заголовок")
            c.expect(!BindPlanner.sameTarget(w1, .appWindow(AppWindowRef(bundleID: BindApps.grokBot, windowTitle: "Другое"))), "окна с разными заголовками")
            c.expect(BindPlanner.sameTarget(.chromeTab(ChromeTabRef(tabID: 1, url: "https://a.com/")),
                                            .chromeTab(ChromeTabRef(tabID: 2, url: "https://A.com"))), "вкладки с тем же адресом")
            c.expect(!BindPlanner.sameTarget(chat, other), "разные источники")
        }
    }

    static func probe(_ c: CheckRunner) {
        c.group("--probe-frontmost") {
            c.expectEqual(ProbeOptions.parse(["--probe-frontmost", "--delay", "3", "--app", "com.google.Chrome", "--prompt"]),
                          ProbeOptions(delay: 3, bundleID: "com.google.Chrome", allowPrompts: true), "ключи")
            c.expectEqual(ProbeOptions.parse(["--delay", "abc"]).delay, 0, "плохая пауза → 0")
            c.expectEqual(ProbeOptions.parse(["--delay", "999"]).delay, 60, "пауза ограничена 60 с")
            c.expectEqual(ProbeOptions.parse(["--delay"]), ProbeOptions(), "ключ без значения игнорируется")

            let report = ProbeReport(
                context: FrontmostContext(bundleID: BindApps.claude, windowTitle: "X"),
                diagnostics: ContextDiagnostics(accessibilityTrusted: false, claudeChat: .noAccessibility),
                capture: .needsManualLink(.claudeChat, suggestedTitle: "X"))
            let json = report.json()
            c.expect(json.contains("\"needsManualLink\"") && json.contains("\"noAccessibility\""), "JSON содержит итог и диагностику")
            let decoded = try JSONDecoder().decode(ProbeReport.self, from: Data(json.utf8))
            c.expectEqual(decoded, report, "JSON читается обратно")
            let captured = CaptureSummary(.captured(.chromeTab(ChromeTabRef(url: "https://a")), suggestedTitle: "T"))
            c.expectEqual(captured.source, .chromeTab, "итог captured с источником")
        }
    }
}
