import Foundation
import JugglerCore

// ChatGPT threads (task CHATGPT): reading ~/.codex/session_index.jsonl, finding a thread by window title,
// binding without a dialog, prefilled link in the dialog for multiple threads, texts and `--probe-frontmost`.

extension BindChecks {
    // Lines as in ~/.codex/session_index.jsonl on the user's Mac (28.10.2026).
    static let clubOld = "01a17477-7849-7471-bc56-8c5460cb624b"
    static let clubNew = "01a17485-58ac-7420-97ee-3c7d03862907"
    static let realIndexLines = [
        #"{"id":"019e8896-7aec-7ff1-8447-1c62c5401f1f","thread_name":"Установить CLI","updated_at":"2026-06-02T13:47:09.428662Z"}"#,
        #"{"id":"\#(clubOld)","thread_name":"Спланировать компьютерный клуб","updated_at":"2026-10-25T19:12:39.536136Z"}"#,
        #"{"id":"\#(clubNew)","thread_name":"Спланировать компьютерный клуб","updated_at":"2026-10-25T19:24:18.668153Z"}"#,
        #"{"id":"\#(clubNew)","thread_name":"Спланировать компьютерный клуб (2)","updated_at":"2026-10-25T19:24:19.612216Z"}"#,
    ]

    static func chatGPTThreads(_ c: CheckRunner) {
        chatGPTIndexParsing(c)
        chatGPTIndexFile(c)
        chatGPTMatcher(c)
        chatGPTCapture(c)
        chatGPTTexts(c)
        chatGPTProbe(c)
    }

    static func index(_ lines: [String]) -> ChatGPTSessionIndexRead {
        let parsed = ChatGPTSessionIndex.parse(Data(lines.joined(separator: "\n").utf8))
        return .loaded(parsed.entries, skippedLines: parsed.skippedLines)
    }

    static func chatGPTIndexParsing(_ c: CheckRunner) {
        c.group("session_index.jsonl: разбор") {
            let real = ChatGPTSessionIndex.parse(Data(realIndexLines.joined(separator: "\n").utf8))
            c.expectEqual(real.entries.map(\.id), [clubNew, clubOld, "019e8896-7aec-7ff1-8447-1c62c5401f1f"],
                          "по треду на id, сначала недавно обновлённые")
            c.expectEqual(real.entries.first?.name, "Спланировать компьютерный клуб (2)", "у переименованного id — последнее название")
            c.expectEqual(real.entries.first?.updatedAt, "2026-10-25T19:24:19.612216Z", "updated_at последней строки")
            c.expectEqual(real.skippedLines, 0, "битых строк нет")

            // Lines out of order: the later updated_at wins even if its line comes earlier.
            let outOfOrder = ChatGPTSessionIndex.parse(Data("""
                {"id":"a1","thread_name":"Новое","updated_at":"2026-10-26T10:00:00Z"}
                {"id":"a1","thread_name":"Старое","updated_at":"2026-10-25T10:00:00.5Z"}
                {"id":"b2","thread_name":"Первое","updated_at":"2026-10-20T10:00:00Z"}
                {"id":"b2","thread_name":"Второе","updated_at":"2026-10-20T10:00:00Z"}
                {"id":"c3","thread_name":"Без даты"}
                {"id":"c3","thread_name":"Без даты, позже"}
                """.utf8)).entries
            c.expectEqual(outOfOrder.first(where: { $0.id == "a1" })?.name, "Новое", "поздний updated_at важнее порядка строк")
            c.expectEqual(outOfOrder.first(where: { $0.id == "b2" })?.name, "Второе", "равные даты — последняя строка")
            c.expectEqual(outOfOrder.first(where: { $0.id == "c3" })?.name, "Без даты, позже", "без дат — последняя строка")
            c.expectEqual(outOfOrder.map(\.id), ["a1", "b2", "c3"], "без даты — в конце списка")

            let messy = ChatGPTSessionIndex.parse(Data((
                "{не json\n"
                + "\n   \n"
                + #"[1,2]"# + "\n"
                + #"{"id":5,"thread_name":"Число"}"# + "\n"
                + #"{"id":"x/../y","thread_name":"Слэш"}"# + "\n"
                + #"{"id":"with space","thread_name":"Пробел"}"# + "\n"
                + #"{"id":"","thread_name":"Пусто"}"# + "\n"
                + #"{"id":"no-name"}"# + "\n"
                + #"{"id":"ok-1","thread_name":"Годный","updated_at":"не дата"}"# + "\r\n"
                + #"{"id":"ok-2","thread_name":"Годный 2","updated_at":""}"#
            ).utf8))
            c.expectEqual(messy.entries.map(\.id).sorted(), ["ok-1", "ok-2"], "битые строки и неподходящие id пропущены")
            c.expectEqual(messy.skippedLines, 7, "пустые строки не считаются битыми")
            c.expectEqual(messy.entries.first(where: { $0.id == "ok-2" })?.updatedAt, nil, "пустой updated_at — нет даты")
            c.expectEqual(messy.entries.first(where: { $0.id == "ok-1" })?.name, "Годный", "строка с \\r\\n читается")

            let garbage = ChatGPTSessionIndex.parse(Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 7919) }))
            c.expect(garbage.entries.isEmpty, "двоичный мусор — пустой список, без ошибок")
            c.expect(ChatGPTSessionIndex.parse(Data()).entries.isEmpty, "пустой файл — пустой список")

            let date = { ChatGPTSessionIndex.parseDate($0)?.timeIntervalSince1970 }
            c.expectEqual(date("2026-10-25T19:24:19Z"), 1_792_956_259, "дата без дробной части")
            c.expect(abs((date("2026-10-25T19:24:19.612216Z") ?? 0) - 1_792_956_259.612216) < 0.000_01, "6 знаков дробной части")
            c.expect(abs((date("2026-06-03T10:19:05.53787Z") ?? 0) - (date("2026-06-03T10:19:05Z") ?? 0) - 0.53787) < 0.000_01,
                     "5 знаков дробной части (как в файле)")
            c.expectEqual(date("2026-10-25T22:24:19.5+03:00"), 1_792_956_259.5, "смещение часового пояса")
            c.expectNil(date("вчера"), "не дата — nil")
            c.expectNil(date("2026-10-25T19:24:19.Z"), "точка без цифр — nil")
        }
    }

    static func chatGPTIndexFile(_ c: CheckRunner) {
        c.group("session_index.jsonl: файл") {
            let fm = FileManager.default
            let dir = fm.temporaryDirectory.appendingPathComponent("jugglinator-codex-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: dir) }
            let url = dir.appendingPathComponent("session_index.jsonl")

            c.expectEqual(ChatGPTSessionIndex.read(url: url), .missing, "нет файла — missing, без ошибок")
            c.expectEqual(ChatGPTSessionIndex.read(url: nil), .missing, "нет пути — missing")
            c.expectEqual(ChatGPTSessionIndex.read(url: dir), .unreadable, "папка вместо файла — unreadable")

            let text = realIndexLines.joined(separator: "\n") + "\n{битая строка\n"
            try Data(text.utf8).write(to: url)
            let before = try Data(contentsOf: url)
            guard case .loaded(let entries, let skipped) = ChatGPTSessionIndex.read(url: url) else {
                c.expect(false, "файл читается"); return
            }
            c.expectEqual(entries.count, 3, "из файла — три треда")
            c.expectEqual(skipped, 1, "битая строка пропущена")
            c.expectEqual(try Data(contentsOf: url), before, "файл не изменён (только чтение)")
            c.expectEqual(ChatGPTSessionIndex.read(url: url, maxSize: 64), .tooLarge, "больше предела — tooLarge, не читается")
            c.expectEqual(ChatGPTSessionIndex.maxFileSize, 16 * 1024 * 1024, "предел по умолчанию — 16 МБ")

            let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
            c.expectEqual(ChatGPTSessionIndex.defaultURL(environment: [:], home: home).path,
                          "/Users/me/.codex/session_index.jsonl", "по умолчанию ~/.codex/session_index.jsonl")
            c.expectEqual(ChatGPTSessionIndex.defaultURL(environment: ["CODEX_HOME": "/tmp/codex"], home: home).path,
                          "/tmp/codex/session_index.jsonl", "CODEX_HOME учитывается")
            c.expectEqual(ChatGPTSessionIndex.defaultURL(environment: ["CODEX_HOME": "  "], home: home).path,
                          "/Users/me/.codex/session_index.jsonl", "пустой CODEX_HOME — как не заданный")
        }
    }

    static func chatGPTMatcher(_ c: CheckRunner) {
        c.group("Поиск треда ChatGPT по заголовку окна") {
            let real = index(realIndexLines)
            let found = ChatGPTThreadMatcher.lookup(windowTitle: "Спланировать компьютерный клуб (2)", index: real, indexPath: "/x")
            c.expectEqual(found.status, .found, "заголовок как на маке — тред найден")
            c.expectEqual(found.uniqueMatch?.id, clubNew, "id треда 01a17485…")
            c.expectEqual(found.uniqueMatch?.link, "codex://threads/\(clubNew)", "ссылка codex://threads/<id>")
            c.expectEqual(found.indexThreadCount, 3, "в диагностике — число тредов")
            c.expectEqual(found.indexPath, "/x", "и путь к файлу")
            c.expectNil(found.prefillLink, "один тред — ссылка в диалог не нужна")

            let older = ChatGPTThreadMatcher.lookup(windowTitle: "Спланировать компьютерный клуб", index: real)
            c.expectEqual(older.matches.map(\.id), [clubOld], "старое название переименованного треда не считается")
            c.expectEqual(older.status, .found, "значит, совпадение одно")

            let spaced = ChatGPTThreadMatcher.lookup(windowTitle: "  Спланировать \u{00A0}компьютерный\n клуб  (2) ", index: real)
            c.expectEqual(spaced.uniqueMatch?.id, clubNew, "лишние пробелы, неразрывный пробел и перевод строки не мешают")
            c.expectEqual(spaced.windowTitle, "Спланировать компьютерный клуб (2)", "в диагностике — заголовок без лишних пробелов")

            c.expectEqual(ChatGPTThreadMatcher.lookup(windowTitle: "Спланировать компьютерный клуб (2) - ChatGPT", index: real).uniqueMatch?.id,
                          clubNew, "хвост « - ChatGPT» срезается (TitleCleaner)")
            c.expectEqual(ChatGPTThreadMatcher.lookup(windowTitle: "спланировать компьютерный клуб (2)", index: real).uniqueMatch?.id,
                          clubNew, "запасное сравнение — без учёта регистра")

            // Decomposed and precomposed letters (й = и + ◌̆): Swift compares strings by canonical equivalence.
            let decomposed = "Установить CLI".decomposedStringWithCanonicalMapping
            c.expectEqual(ChatGPTThreadMatcher.lookup(windowTitle: decomposed, index: real).status, .found, "Unicode-нормализация не мешает")

            let twins = index([
                #"{"id":"t-old","thread_name":"Отчёт","updated_at":"2026-10-20T10:00:00Z"}"#,
                #"{"id":"t-new","thread_name":"Отчёт ","updated_at":"2026-10-27T10:00:00Z"}"#,
                #"{"id":"t-mid","thread_name":"отчёт - ChatGPT","updated_at":"2026-10-25T10:00:00Z"}"#,
                #"{"id":"t-other","thread_name":"Отчёт за май","updated_at":"2026-10-28T10:00:00Z"}"#,
            ])
            let ambiguous = ChatGPTThreadMatcher.lookup(windowTitle: "Отчёт", index: twins)
            c.expectEqual(ambiguous.status, .ambiguous, "два треда «Отчёт» — неоднозначно")
            c.expectEqual(ambiguous.matches.map(\.id), ["t-new", "t-old"],
                          "точные совпадения, сначала последний обновлённый; запасное сравнение не подмешивается")
            c.expectNil(ambiguous.uniqueMatch, "без единственного совпадения — без автопривязки")
            c.expectEqual(ambiguous.prefillLink, "codex://threads/t-new", "в диалог — ссылка на последний обновлённый")
            c.expectEqual(ChatGPTThreadMatcher.lookup(windowTitle: "ОТЧЁТ", index: twins).matches.map(\.id), ["t-new", "t-mid", "t-old"],
                          "без точного — все совпадения без учёта регистра и хвостов")

            c.expectEqual(ChatGPTThreadMatcher.lookup(windowTitle: "Чего нет", index: real).status, .notFound, "нет треда — notFound")
            c.expectEqual(ChatGPTThreadMatcher.lookup(windowTitle: "ChatGPT", index: real).status, .notFound,
                          "окно без треда («ChatGPT») — notFound")
            c.expectEqual(ChatGPTThreadMatcher.lookup(windowTitle: nil, index: real).status, .noWindowTitle, "нет заголовка — noWindowTitle")
            c.expectEqual(ChatGPTThreadMatcher.lookup(windowTitle: "  ", index: real).status, .noWindowTitle, "пустой заголовок — noWindowTitle")
            c.expectEqual(ChatGPTThreadMatcher.lookup(windowTitle: "X", index: .missing).status, .indexMissing, "нет файла — indexMissing")
            c.expectEqual(ChatGPTThreadMatcher.lookup(windowTitle: "X", index: .tooLarge).status, .indexTooLarge, "большой файл — indexTooLarge")
            c.expectEqual(ChatGPTThreadMatcher.lookup(windowTitle: "X", index: .unreadable).status, .indexUnreadable, "не читается — indexUnreadable")
            c.expect(found.applies(toWindowTitle: " Спланировать компьютерный клуб (2)"), "поиск относится к тому же окну")
            c.expect(!found.applies(toWindowTitle: "Другое окно"), "и не относится к другому")
        }
    }

    static func chatGPTCapture(_ c: CheckRunner) {
        c.group("Привязка треда ChatGPT по названию") {
            let real = index(realIndexLines)
            let title = "Спланировать компьютерный клуб (2)"
            let context = FrontmostContext(bundleID: "com.openai.codex", appName: "ChatGPT", windowTitle: title)
            let lookup = ChatGPTThreadMatcher.lookup(windowTitle: title, index: real)
            let captured = BindingCapture.capture(context: context, chatGPTLookup: lookup)
            let expected = TaskBinding.chatGPTThread(ChatGPTThreadRef(threadID: clubNew, title: title))
            c.expectEqual(captured, .captured(expected, suggestedTitle: title), "найден один тред → привязка сразу, без диалога")
            c.expectEqual(CaptureSummary(captured).status, "captured", "в --probe-frontmost — captured")

            let renamed = index([#"{"id":"r1","thread_name":"Длинное  название   треда","updated_at":"2026-10-27T10:00:00Z"}"#])
            let renamedContext = FrontmostContext(bundleID: "com.openai.codex", windowTitle: "Длинное название треда - ChatGPT")
            c.expectEqual(BindingCapture.capture(context: renamedContext,
                                                 chatGPTLookup: ChatGPTThreadMatcher.lookup(windowTitle: renamedContext.windowTitle, index: renamed)),
                          .captured(.chatGPTThread(ChatGPTThreadRef(threadID: "r1", title: "Длинное название треда - ChatGPT")),
                                    suggestedTitle: "Длинное название треда"),
                          "название задачи — по треду, в привязке — заголовок окна")

            let stale = ChatGPTThreadMatcher.lookup(windowTitle: "Установить CLI", index: real)
            c.expectEqual(BindingCapture.capture(context: context, chatGPTLookup: stale), .needsManualLink(.chatGPTThread, suggestedTitle: title),
                          "поиск для другого окна не используется")
            c.expectEqual(BindingCapture.capture(context: context), .needsManualLink(.chatGPTThread, suggestedTitle: title),
                          "без поиска — прежний диалог ссылки")
            let notFound = ChatGPTThreadMatcher.lookup(windowTitle: "Новый тред", index: real)
            let notFoundContext = FrontmostContext(bundleID: "com.openai.codex", windowTitle: "Новый тред")
            c.expectEqual(BindingCapture.capture(context: notFoundContext, chatGPTLookup: notFound),
                          .needsManualLink(.chatGPTThread, suggestedTitle: "Новый тред"), "нет совпадения → диалог ссылки")
            c.expectNil(BindingCapture.chatGPTPrefillLink(lookup: notFound, windowTitle: "Новый тред"), "и ссылка не вставлена")

            let withID = FrontmostContext(bundleID: "com.openai.codex", windowTitle: title, chatGPTThreadID: "explicit")
            c.expectEqual(BindingCapture.capture(context: withID, chatGPTLookup: lookup),
                          .captured(.chatGPTThread(ChatGPTThreadRef(threadID: "explicit", title: title)), suggestedTitle: title),
                          "известный id треда важнее поиска по названию")
            let claude = FrontmostContext(bundleID: BindApps.claude, windowTitle: title)
            c.expectEqual(BindingCapture.capture(context: claude, chatGPTLookup: lookup), .needsManualLink(.claudeChat, suggestedTitle: title),
                          "поиск ChatGPT не влияет на Claude")

            let twins = index([
                #"{"id":"t-old","thread_name":"Отчёт","updated_at":"2026-10-20T10:00:00Z"}"#,
                #"{"id":"t-new","thread_name":"Отчёт","updated_at":"2026-10-27T10:00:00Z"}"#,
            ])
            let twinContext = FrontmostContext(bundleID: "com.openai.codex", windowTitle: "Отчёт")
            let twinLookup = ChatGPTThreadMatcher.lookup(windowTitle: "Отчёт", index: twins)
            c.expectEqual(BindingCapture.capture(context: twinContext, chatGPTLookup: twinLookup),
                          .needsManualLink(.chatGPTThread, suggestedTitle: "Отчёт"), "несколько тредов → диалог ссылки")
            let prefill = BindingCapture.chatGPTPrefillLink(lookup: twinLookup, windowTitle: "Отчёт")
            c.expectEqual(prefill, "codex://threads/t-new", "с уже вставленной ссылкой на последний обновлённый")
            c.expectNil(BindingCapture.chatGPTPrefillLink(lookup: twinLookup, windowTitle: "Другое"), "для другого окна ссылка не вставляется")
            c.expectEqual(BindingCapture.bindingFromManualLink(prefill ?? "", expected: .chatGPTThread, windowTitle: "Отчёт"),
                          .binding(.chatGPTThread(ChatGPTThreadRef(threadID: "t-new", title: "Отчёт"))),
                          "вставленная ссылка привязывается кнопкой «Привязать»")

            // Current-task detection is unchanged: the switch context has no thread id, the thread is recognized by window title.
            var document = TasksDocument()
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let other = JugglerTask(title: "Другое", binding: .chatGPTThread(ChatGPTThreadRef(threadID: clubOld, title: "Спланировать компьютерный клуб")))
            document.tasks.append(other)
            let id = BindPlanner.createTask(in: &document, title: title, binding: expected, now: now)
            let switching = FrontmostContext(bundleID: "com.openai.codex", windowTitle: title)
            c.expectEqual(CurrentTaskResolver.match(context: switching, tasks: document.tasks), id, "переключение: тред узнаётся по заголовку окна")
            c.expectEqual(CurrentTaskResolver.score(expected, against: switching), .sameTitle, "оценка — по заголовку, как раньше")
            c.expectEqual(BindPlanner.plan(document: document, binding: expected), .alreadyBound(taskID: id, number: 2),
                          "повторная привязка того же треда — «уже привязан»")
        }
    }

    static func chatGPTTexts(_ c: CheckRunner) {
        c.group("Тексты диалога ссылки ChatGPT") {
            let real = index(realIndexLines)
            for trusted in [true, false] {
                let generic = BindTexts.manualLinkMessage(.chatGPTThread, accessibilityTrusted: trusted)
                c.expect(generic.contains("codex://threads/<id>"), "общий текст называет ссылку (AX \(trusted))")
                c.expect(!generic.contains("не умеет"), "и больше не говорит, что Jugglinator не умеет искать тред (AX \(trusted))")
            }
            c.expect(BindTexts.manualLinkMessage(.chatGPTThread, accessibilityTrusted: false).contains("Универсальный доступ"),
                     "без Accessibility — причина в разрешении")

            let twins = ChatGPTThreadMatcher.lookup(windowTitle: "Отчёт", index: index([
                #"{"id":"a","thread_name":"Отчёт","updated_at":"2026-10-20T10:00:00Z"}"#,
                #"{"id":"b","thread_name":"Отчёт","updated_at":"2026-10-27T10:00:00Z"}"#,
            ]))
            let ambiguous = BindTexts.chatGPTLinkMessage(lookup: twins, accessibilityTrusted: true)
            c.expect(ambiguous.contains("«Отчёт»") && ambiguous.contains("(2)") && ambiguous.contains("последний обновлённый"),
                     "несколько тредов: название, число и что вставлено")
            let missing = BindTexts.chatGPTLinkMessage(lookup: ChatGPTThreadMatcher.lookup(windowTitle: "Нет", index: real), accessibilityTrusted: true)
            c.expect(missing.contains("«Нет»") && missing.contains("~/.codex/session_index.jsonl") && missing.contains("codex://threads/<id>"),
                     "не найден: название, файл и какая ссылка нужна")
            let noFile = BindTexts.chatGPTLinkMessage(lookup: ChatGPTThreadMatcher.lookup(windowTitle: "X", index: .missing), accessibilityTrusted: true)
            c.expect(noFile.contains("не найден") && noFile.contains("session_index.jsonl"), "нет файла — так и сказано")
            let noTitle = BindTexts.chatGPTLinkMessage(lookup: ChatGPTThreadMatcher.lookup(windowTitle: nil, index: real), accessibilityTrusted: false)
            c.expect(noTitle.contains("Универсальный доступ"), "нет заголовка без Accessibility — причина в разрешении")
        }
    }

    static func chatGPTProbe(_ c: CheckRunner) {
        c.group("--probe-frontmost: поиск треда ChatGPT") {
            c.expectEqual(ProbeOptions.parse(["--probe-frontmost", "--app", "com.openai.codex", "--window-title", "Спланировать клуб"]),
                          ProbeOptions(bundleID: "com.openai.codex", windowTitle: "Спланировать клуб"), "ключ --window-title")
            c.expectNil(ProbeOptions.parse(["--window-title"]).windowTitle, "ключ без значения игнорируется")

            let title = "Спланировать компьютерный клуб (2)"
            let lookup = ChatGPTThreadMatcher.lookup(windowTitle: title, index: index(realIndexLines), indexPath: "/Users/me/.codex/session_index.jsonl")
            let context = FrontmostContext(bundleID: "com.openai.codex", windowTitle: title)
            let report = ProbeReport(
                context: context,
                diagnostics: ContextDiagnostics(accessibilityTrusted: true, windowTitleRead: true, chatGPTThread: lookup),
                capture: BindingCapture.capture(context: context, chatGPTLookup: lookup))
            let json = report.json()
            c.expect(json.contains("\"chatGPTThread\"") && json.contains("\"status\" : \"found\"") && json.contains(clubNew),
                     "JSON показывает итог поиска и id треда")
            c.expect(json.contains("\"captured\""), "и привязку без диалога")
            c.expectEqual(try JSONDecoder().decode(ProbeReport.self, from: Data(json.utf8)), report, "JSON читается обратно")

            let old = #"{"accessibilityTrusted":true,"usedRememberedApp":false,"windowTitleRead":true,"claudeCandidateURLs":[],"notes":[]}"#
            c.expectNil(try JSONDecoder().decode(ContextDiagnostics.self, from: Data(old.utf8)).chatGPTThread,
                        "диагностика без поля chatGPTThread читается")
        }
    }
}
