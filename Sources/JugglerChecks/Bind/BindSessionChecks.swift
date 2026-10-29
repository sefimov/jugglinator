import Foundation
import JugglerCore

// Claude Code sessions (task SESSION): reading the id from Accessibility, binding without a dialog,
// pasted links, dialog texts and claude-code-sessions metadata.

extension BindChecks {
    static let sessionUUID = "fae5c400-6c06-4fa7-8cb8-eecc594fc296"
    static var sessionID: String { "local_\(sessionUUID)" }

    static func sessions(_ c: CheckRunner) {
        sessionExtractor(c)
        sessionCapture(c)
        sessionManualLinks(c)
        sessionMetadata(c)
    }

    static func sessionExtractor(_ c: CheckRunner) {
        c.group("Сессия Claude Code из Accessibility") {
            // As on the user's Mac: the Code tab, `--probe-frontmost` 28.10.2026.
            let code = ["file:///Applications/Claude.app/Contents/Resources/app.asar/index.html",
                        "https://claude.ai/epitaxy/\(sessionID)"]
            c.expectEqual(ClaudeChatURLExtractor.sessionID(fromCandidates: code), sessionID, "id сессии из адреса веб-области")
            c.expectNil(ClaudeChatURLExtractor.conversationID(fromCandidates: code), "сессия — не чат")
            c.expectEqual(ClaudeChatURLExtractor.status(candidates: code, treeAvailable: true, accessibilityTrusted: true),
                          .codeSession, "статус codeSession")
            c.expectEqual(ClaudeChatURLExtractor.link(fromCandidates: code), .claudeCodeSession(sessionID: sessionID), "ссылка на сессию")
            c.expectNil(ClaudeChatURLExtractor.sessionID(fromCandidates: [sessionID]), "голый id в дереве не считается адресом")
            let chat = ["https://claude.ai/chat/\(uuid)", "https://claude.ai/epitaxy/\(sessionID)"]
            c.expectEqual(ClaudeChatURLExtractor.conversationID(fromCandidates: chat), uuid, "первым идёт чат — берётся чат")
            c.expectNil(ClaudeChatURLExtractor.sessionID(fromCandidates: chat), "и тогда сессии нет")
            c.expectEqual(ClaudeChatURLExtractor.status(candidates: chat, treeAvailable: true, accessibilityTrusted: true), .read,
                          "чат — по-прежнему read")
        }
    }

    static func sessionCapture(_ c: CheckRunner) {
        c.group("Привязка сессии Claude Code") {
            let titled = BindingCapture.capture(context: FrontmostContext(
                bundleID: BindApps.claude, appName: "Claude", windowTitle: "Claude",
                claudeCodeSessionID: sessionID, claudeCodeSessionTitle: "  Сессии Claude Code в Juggler "))
            c.expectEqual(titled, .captured(.claudeCodeSession(ClaudeCodeSessionRef(sessionID: sessionID, title: "Сессии Claude Code в Juggler")),
                                            suggestedTitle: "Сессии Claude Code в Juggler"),
                          "вкладка Code → сессия сразу, название из метаданных")

            let byWindow = BindingCapture.capture(context: FrontmostContext(
                bundleID: BindApps.claude, windowTitle: "Ревью PR - Claude", claudeCodeSessionID: sessionID))
            c.expectEqual(byWindow, .captured(.claudeCodeSession(ClaudeCodeSessionRef(sessionID: sessionID, title: "Ревью PR")),
                                              suggestedTitle: "Ревью PR"),
                          "без метаданных — название из очищенного заголовка окна")

            let bare = BindingCapture.capture(context: FrontmostContext(
                bundleID: BindApps.claude, windowTitle: "Claude", claudeCodeSessionID: sessionID, claudeCodeSessionTitle: ""))
            c.expectEqual(bare, .captured(.claudeCodeSession(ClaudeCodeSessionRef(sessionID: sessionID, title: "")),
                                          suggestedTitle: BindTexts.defaultSessionTaskTitle),
                          "ни названия, ни заголовка → «Сессия Claude Code»")

            let long = String(repeating: "очень длинное название ", count: 10)
            if case .captured(_, let title) = BindingCapture.capture(context: FrontmostContext(
                bundleID: BindApps.claude, claudeCodeSessionID: sessionID, claudeCodeSessionTitle: long)) {
                c.expect(title.count <= 80 && title.hasSuffix("…"), "длинное название обрезается")
            } else {
                c.expect(false, "длинное название: нет привязки")
            }

            let bogus = BindingCapture.capture(context: FrontmostContext(
                bundleID: BindApps.claude, windowTitle: "Claude", claudeCodeSessionID: "local_xyz"))
            c.expectEqual(bogus, .needsManualLink(.claudeChat, suggestedTitle: "Новая задача"), "кривой id сессии → как раньше, запрос ссылки")

            let chatFirst = BindingCapture.capture(context: FrontmostContext(
                bundleID: BindApps.claude, windowTitle: "Чат - Claude", claudeConversationID: uuid, claudeCodeSessionID: sessionID))
            if case .captured(let binding, _) = chatFirst {
                c.expectEqual(binding.source, .claudeChat, "id чата прочитан — привязывается чат")
            } else {
                c.expect(false, "чат с id: нет привязки")
            }

            let a = TaskBinding.claudeCodeSession(ClaudeCodeSessionRef(sessionID: sessionID, title: "A"))
            let b = TaskBinding.claudeCodeSession(ClaudeCodeSessionRef(sessionID: sessionID.uppercased(), title: "B"))
            c.expect(BindPlanner.sameTarget(a, b), "та же сессия при другом названии и регистре")
            c.expect(!BindPlanner.sameTarget(a, .claudeCodeSession(ClaudeCodeSessionRef(sessionID: "local_\(uuid)"))), "разные сессии")
            c.expect(!BindPlanner.sameTarget(a, .claudeChat(ClaudeChatRef(conversationID: sessionUUID))), "сессия и чат с тем же UUID — разное")
            let doc = TasksDocument(tasks: [JugglerTask(title: "Сессия", binding: a)])
            c.expectEqual(BindPlanner.plan(document: doc, binding: b), .alreadyBound(taskID: doc.tasks[0].id, number: 1),
                          "сессия уже привязана → её задача")

            let summary = CaptureSummary(titled)
            c.expectEqual(summary.source, .claudeCodeSession, "--probe-frontmost: источник — сессия")
            let report = ProbeReport(context: FrontmostContext(bundleID: BindApps.claude, claudeCodeSessionID: sessionID),
                                     diagnostics: ContextDiagnostics(accessibilityTrusted: true, claudeChat: .codeSession), capture: titled)
            let json = report.json()
            c.expect(json.contains("\"claudeCodeSessionID\" : \"\(sessionID)\"") && json.contains("\"codeSession\""),
                     "--probe-frontmost: id сессии и статус в JSON")
            c.expectEqual(try JSONDecoder().decode(ProbeReport.self, from: Data(json.utf8)), report, "JSON с сессией читается обратно")
        }
    }

    static func sessionManualLinks(_ c: CheckRunner) {
        c.group("Ссылка на сессию и «Поделиться» в диалоге") {
            let expected = TaskBinding.claudeCodeSession(ClaudeCodeSessionRef(sessionID: sessionID, title: "Claude"))
            for link in ["https://claude.ai/epitaxy/\(sessionID)", "claude://claude.ai/epitaxy/\(sessionID)", " \(sessionID.uppercased()) "] {
                c.expectEqual(BindingCapture.bindingFromManualLink(link, expected: .claudeChat, windowTitle: "Claude"), .binding(expected),
                              "вставлена сессия: \(link.trimmingCharacters(in: .whitespaces))")
            }
            c.expectEqual(BindingCapture.bindingFromManualLink(sessionID, expected: .chatGPTThread, windowTitle: "Claude"), .binding(expected),
                          "id сессии принимается и в диалоге ChatGPT")

            let share = BindingCapture.bindingFromManualLink("https://claude.ai/share/0b6a1f53-1c2e-4f1e-9a1d-2b4c6d8e0f12",
                                                             expected: .claudeChat, windowTitle: nil)
            c.expectEqual(share, .invalid(BindTexts.shareLinkNotSupported), "ссылка «Поделиться» распознана и отклонена")
            c.expect(BindTexts.shareLinkNotSupported.contains("«Поделиться»") && BindTexts.shareLinkNotSupported.contains("claude.ai/chat/"),
                     "пояснение: что не так и что подойдёт")
            c.expectEqual(BindingCapture.bindingFromManualLink("https://example.com/x", expected: .claudeChat, windowTitle: nil),
                          .invalid(BindTexts.unrecognizedLink(.claudeChat)), "прочий мусор — общее «не распознана»")
            c.expect(BindTexts.unrecognizedLink(.claudeChat).contains("epitaxy/local_"), "в «не распознана» есть формат сессии")

            for trusted in [true, false] {
                let message = BindTexts.manualLinkMessage(.claudeChat, accessibilityTrusted: trusted)
                c.expect(!message.contains("Поделиться →") && !message.contains("Копировать ссылку"),
                         "диалог не советует «Поделиться → Копировать ссылку» (AX \(trusted))")
                c.expect(message.contains("claude.ai/chat/") && message.contains("epitaxy/local_"),
                         "диалог называет адрес чата и ссылку сессии (AX \(trusted))")
            }
            c.expectEqual(BindTexts.manualLinkTitle(.claudeCodeSession), "Ссылка на сессию Claude Code", "заголовок для сессии")
        }
    }

    static func sessionMetadata(_ c: CheckRunner) {
        c.group("Метаданные claude-code-sessions") {
            let fm = FileManager.default
            let root = fm.temporaryDirectory.appendingPathComponent("juggler-sessions-\(UUID().uuidString)", isDirectory: true)
            defer { try? fm.removeItem(at: root) }
            func write(_ text: String, _ components: [String]) throws {
                let url = components.reduce(root) { $0.appendingPathComponent($1) }
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(text.utf8).write(to: url)
            }

            c.expectNil(ClaudeCodeSessionMetadata.info(sessionID: sessionID, root: root), "нет папки — nil, без ошибок")
            c.expectNil(ClaudeCodeSessionMetadata.info(sessionID: sessionID, root: nil), "нет корня — nil")

            let full = #"{"sessionId":"\#(sessionID)","title":" Сессии Code ","cwd":"/Users/me/work/juggler","isArchived":false,"lastActivityAt":1792762529268,"model":"x"}"#
            try write(full, ["528e4771-d70f-4ecd-b1ee-7feb6fe7d772", "5f0bd1ec-d049-4fca-8044-a9ea78d7ddb3", "\(sessionID).json"])
            try write("{}", ["528e4771-d70f-4ecd-b1ee-7feb6fe7d772", "5f0bd1ec-d049-4fca-8044-a9ea78d7ddb3", "scheduled-tasks.json"])
            let info = ClaudeCodeSessionMetadata.info(sessionID: sessionID.uppercased(), root: root)
            c.expectEqual(info, ClaudeCodeSessionInfo(sessionID: sessionID, title: "Сессии Code", cwd: "/Users/me/work/juggler", isArchived: false),
                          "раскладка root/<uuid>/<uuid>/local_<uuid>.json, id без учёта регистра")

            let deep = "local_11111111-2222-4333-8444-555555555555"
            try write(#"{"sessionId":"\#(deep)","title":"Глубже"}"#, ["a", "b", "c", "\(deep).json"])
            c.expectEqual(ClaudeCodeSessionMetadata.info(sessionID: deep, root: root)?.title, "Глубже", "другая вложенность — запасной поиск")

            let sparse = "local_22222222-3333-4444-8555-666666666666"
            try write(#"{"isArchived":true}"#, ["x", "y", "\(sparse).json"])
            c.expectEqual(ClaudeCodeSessionMetadata.info(sessionID: sparse, root: root),
                          ClaudeCodeSessionInfo(sessionID: sparse, title: "", cwd: nil, isArchived: true), "нет полей — пустые значения")

            let broken = "local_33333333-4444-4555-8666-777777777777"
            try write("{не json", ["x", "y", "\(broken).json"])
            c.expectNil(ClaudeCodeSessionMetadata.info(sessionID: broken, root: root), "битый JSON — nil")

            let foreign = "local_44444444-5555-4666-8777-888888888888"
            try write(#"{"sessionId":"\#(sessionID)","title":"Чужая"}"#, ["x", "y", "\(foreign).json"])
            c.expectNil(ClaudeCodeSessionMetadata.info(sessionID: foreign, root: root), "внутри чужой id — не наши метаданные")

            c.expectNil(ClaudeCodeSessionMetadata.fileURL(sessionID: "../../etc/passwd", root: root), "не id сессии — файл не ищется")
            c.expectNil(ClaudeCodeSessionMetadata.parse(Data("[1,2]".utf8)), "не объект — nil")
            c.expectEqual(ClaudeCodeSessionMetadata.parse(Data(#"{"sessionId":"garbage","title":5}"#.utf8)),
                          ClaudeCodeSessionInfo(sessionID: "", title: ""), "поля неверного типа игнорируются")
            c.expect(ClaudeCodeSessionMetadata.defaultRoot()?.path.hasSuffix("Application Support/Claude/claude-code-sessions") == true,
                     "папка по умолчанию — Application Support/Claude/claude-code-sessions")
        }
    }
}
