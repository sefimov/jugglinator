import Foundation
import JugglerCore

// Проверки чистой логики SWITCH (Sources/JugglerCore/Switch/):
// разбор и показ хоткеев, назначения и их хранение, выбор задачи, тексты карточки.

enum SwitchChecks: CheckSuite {
    static let name = "Switch"

    static func run(_ c: CheckRunner) {
        hotkeyFormatChecks(c)
        hotkeyParseChecks(c)
        validationChecks(c)
        assignmentChecks(c)
        storageChecks(c)
        plannerChecks(c)
        cardChecks(c)
    }

    static let section = KeyCode.isoSection
    static let grave = KeyCode.ansiGrave

    static func hotkeyFormatChecks(_ c: CheckRunner) {
        c.group("хоткей: показ и маски Carbon") {
            c.expectEqual(Hotkey(keyCode: section, modifiers: [.control]).displayString, "⌃§", "⌃ + § на ISO")
            c.expectEqual(Hotkey(keyCode: grave, modifiers: [.control, .shift]).displayString, "⌃⇧`", "⌃⇧ + ` на ANSI")
            c.expectEqual(
                Hotkey(keyCode: 0x28, modifiers: [.command, .shift, .option, .control]).displayString, "⌃⌥⇧⌘K",
                "порядок модификаторов как в macOS")
            c.expectEqual(Hotkey(keyCode: 0x7A, modifiers: []).displayString, "F1", "функциональная клавиша")
            c.expectEqual(Hotkey(keyCode: 0x31, modifiers: [.option]).displayString, "⌥Пробел", "пробел по-русски")
            c.expectEqual(KeyCode.displayName(0x7F), "Клавиша 127", "неизвестный код")
            c.expectEqual(Hotkey(keyCode: section, modifiers: [.control, .shift]).storageString, "control+shift+#10", "строка для хранения")

            c.expectEqual(HotkeyModifiers([.control]).carbonFlags, 0x1000, "⌃ → controlKey")
            c.expectEqual(HotkeyModifiers([.control, .option]).carbonFlags, 0x1800, "⌃⌥ → controlKey|optionKey")
            c.expectEqual(HotkeyModifiers([.shift, .command]).carbonFlags, 0x0300, "⇧⌘ → shiftKey|cmdKey")
            c.expectEqual(HotkeyModifiers(carbonFlags: 0x1A00), [.control, .option, .shift], "обратно из маски Carbon")
            c.expectEqual(HotkeyModifiers(carbonFlags: 0x0400), [], "Caps Lock в маске игнорируется")
            c.expectEqual(Hotkey(keyCode: 1, modifiers: HotkeyModifiers(rawValue: 0xFF)).modifiers, .all, "лишние биты отбрасываются")
        }
    }

    static func hotkeyParseChecks(_ c: CheckRunner) {
        c.group("хоткей: разбор строки") {
            let ctrlSection = Hotkey(keyCode: section, modifiers: [.control])
            c.expectEqual(Hotkey(parsing: "⌃§"), ctrlSection, "символы: ⌃§")
            c.expectEqual(Hotkey(parsing: "ctrl+section"), ctrlSection, "слова: ctrl+section")
            c.expectEqual(Hotkey(parsing: " Control + #10 "), ctrlSection, "явный код и пробелы")
            c.expectEqual(Hotkey(parsing: "ctrl+0x0A"), ctrlSection, "шестнадцатеричный код")
            c.expectEqual(Hotkey(parsing: "⌃⇧`"), Hotkey(keyCode: grave, modifiers: [.control, .shift]), "символы: ⌃⇧`")
            c.expectEqual(Hotkey(parsing: "ctrl+ё"), Hotkey(keyCode: grave, modifiers: [.control]), "«ё» — та же физическая клавиша, что `")
            c.expectEqual(Hotkey(parsing: "cmd+opt+k"), Hotkey(keyCode: 0x28, modifiers: [.command, .option]), "буква в нижнем регистре")
            c.expectEqual(Hotkey(parsing: "⌘⌥+F5"), Hotkey(keyCode: 0x60, modifiers: [.command, .option]), "символы модификаторов перед «+»")
            c.expectEqual(Hotkey(parsing: "shift+shift+ctrl+space"), Hotkey(keyCode: 0x31, modifiers: [.shift, .control]), "повтор модификатора")
            c.expectEqual(Hotkey(parsing: "F12"), Hotkey(keyCode: 0x6F, modifiers: []), "без модификаторов")

            c.expectNil(Hotkey(parsing: ""), "пустая строка")
            c.expectNil(Hotkey(parsing: "⌃"), "только модификатор")
            c.expectNil(Hotkey(parsing: "ctrl+"), "нет клавиши после «+»")
            c.expectNil(Hotkey(parsing: "hyper+k"), "неизвестный модификатор")
            c.expectNil(Hotkey(parsing: "ctrl+ж"), "символ раскладки, а не физическая клавиша")
            c.expectNil(Hotkey(parsing: "ctrl+#200"), "код вне диапазона")
            c.expectNil(Hotkey(parsing: "ctrl++k"), "пустой элемент")

            var roundTrip = true
            for code in UInt32(0)..<0x80 where !KeyCode.modifierKeys.contains(code) {
                let hotkey = Hotkey(keyCode: code, modifiers: [.control, .option])
                if Hotkey(parsing: hotkey.storageString) != hotkey { roundTrip = false }
            }
            c.expect(roundTrip, "storageString разбирается обратно для всех кодов 0–127")
            let shownRoundTrip = [section, grave, 0x00, 0x12, 0x31, 0x7A, 0x7E].allSatisfy { code in
                let hotkey = Hotkey(keyCode: code, modifiers: [.control, .shift])
                return Hotkey(parsing: hotkey.displayString) == hotkey
            }
            c.expect(shownRoundTrip, "displayString разбирается обратно для частых клавиш")
        }
    }

    static func validationChecks(_ c: CheckRunner) {
        c.group("хоткей: проверка записанного сочетания") {
            c.expectNil(HotkeyValidator.validate(Hotkey(keyCode: section, modifiers: [.control])), "⌃§ годится")
            c.expectEqual(HotkeyValidator.validate(Hotkey(keyCode: 0x00, modifiers: [])), .needsModifier, "буква без модификатора")
            c.expectEqual(HotkeyValidator.validate(Hotkey(keyCode: 0x00, modifiers: [.shift])), .needsModifier, "только ⇧ мешает набору")
            c.expectNil(HotkeyValidator.validate(Hotkey(keyCode: 0x60, modifiers: [])), "F5 без модификатора годится")
            c.expectEqual(HotkeyValidator.validate(Hotkey(keyCode: 0x3B, modifiers: [.control])), .modifierOnly, "только клавиша Control")
            c.expectEqual(HotkeyValidator.validate(Hotkey(keyCode: 0x90, modifiers: [.control])), .invalidKey, "код вне диапазона")
            c.expect(HotkeyValidationError.conflict(.nextTask).message.contains("Следующая задача"), "текст конфликта называет действие")
        }
    }

    static func assignmentChecks(_ c: CheckRunner) {
        c.group("назначения хоткеев") {
            c.expectEqual(KeyboardKind.fromLayoutType(0x4953_4F20), .iso, "'ISO ' → ISO")
            c.expectEqual(KeyboardKind.fromLayoutType(0x414E_5349), .ansi, "'ANSI' → ANSI")
            c.expectEqual(KeyboardKind.fromLayoutType(0x4A49_5320), .jis, "'JIS ' → JIS")
            c.expectEqual(KeyboardKind.fromLayoutType(0), .ansi, "неизвестный тип → ANSI")
            c.expectEqual(KeyboardKind.iso.keyAboveTab, section, "ISO: над Tab — §")
            c.expectEqual(KeyboardKind.ansi.keyAboveTab, grave, "ANSI: над Tab — `")

            let iso = HotkeyAssignments.defaults(for: .iso)
            c.expectEqual(iso[.nextTask], Hotkey(keyCode: section, modifiers: [.control]), "по умолчанию «следующая» ⌃§")
            c.expectEqual(iso[.previousTask], Hotkey(keyCode: section, modifiers: [.control, .shift]), "по умолчанию «предыдущая» ⌃⇧§")
            c.expectEqual(iso[.bindCurrentChat], Hotkey(keyCode: section, modifiers: [.control, .option]), "по умолчанию «привязать» ⌃⌥§")
            c.expectEqual(HotkeyAssignments.defaults(for: .ansi)[.nextTask]?.displayString, "⌃`", "ANSI: ⌃`")
            c.expectEqual(iso[.toggleDone], Hotkey(keyCode: 2, modifiers: [.control, .option]), "по умолчанию «сделано» ⌃⌥D (kVK_ANSI_D)")
            c.expectEqual(HotkeyAssignments.defaults(for: .ansi)[.toggleDone], iso[.toggleDone], "⌃⌥D одинаково на ISO и ANSI")
            c.expectEqual(iso[.toggleDone]?.displayString, "⌃⌥D", "показ ⌃⌥D")
            c.expectEqual(iso.hotkeys.count, HotkeyAction.allCases.count, "у каждого действия есть умолчание")
            for kind in KeyboardKind.allCases {
                let defaults = HotkeyAssignments.defaults(for: kind)
                c.expectEqual(Set(defaults.hotkeys.values).count, HotkeyAction.allCases.count, "умолчания не пересекаются (\(kind.rawValue))")
            }

            var overrides = HotkeyOverrides()
            let f5 = Hotkey(keyCode: 0x60, modifiers: [.control])
            c.expectNil(overrides.assign(f5, to: .nextTask, defaults: iso), "своё сочетание принимается")
            var effective = HotkeyAssignments.resolve(overrides: overrides, defaults: iso)
            c.expectEqual(effective[.nextTask], f5, "своё сочетание побеждает умолчание")
            c.expectEqual(effective[.previousTask], iso[.previousTask], "остальные — по умолчанию")

            c.expectEqual(
                overrides.assign(iso[.bindCurrentChat]!, to: .previousTask, defaults: iso), .conflict(.bindCurrentChat),
                "занятое другим действием отклоняется")
            c.expectEqual(overrides.assign(f5, to: .nextTask, defaults: iso), nil, "то же сочетание тому же действию — не конфликт")
            c.expectEqual(
                overrides.assign(Hotkey(keyCode: 0x00, modifiers: []), to: .nextTask, defaults: iso), .needsModifier,
                "недопустимое отклоняется без изменений")
            c.expectEqual(overrides.hotkeys[.nextTask], f5, "после отказа назначение не изменилось")

            c.expectNil(overrides.assign(iso[.nextTask]!, to: .nextTask, defaults: iso), "возврат к умолчанию записью")
            c.expect(overrides.hotkeys.isEmpty, "совпадение с умолчанием не хранится")

            // Своё сочетание совпало с умолчанием другого действия (например, после смены клавиатуры).
            let clash = HotkeyOverrides([.nextTask: iso[.bindCurrentChat]!])
            effective = HotkeyAssignments.resolve(overrides: clash, defaults: iso)
            c.expectEqual(effective[.nextTask], iso[.bindCurrentChat], "своё сочетание сохраняется")
            c.expectNil(effective[.bindCurrentChat], "конфликтующее умолчание снимается")
            let twins = HotkeyOverrides([.nextTask: f5, .previousTask: f5])
            effective = HotkeyAssignments.resolve(overrides: twins, defaults: iso)
            c.expectEqual([effective[.nextTask], effective[.previousTask]], [f5, nil], "два одинаковых своих — остаётся первое")
            c.expectEqual(effective.action(using: f5), .nextTask, "поиск действия по сочетанию")

            var reset = HotkeyOverrides([.nextTask: f5])
            reset.reset(.nextTask)
            c.expect(reset.hotkeys.isEmpty, "reset возвращает умолчание")
        }
    }

    static func storageChecks(_ c: CheckRunner) {
        c.group("хранение хоткеев") {
            let f5 = Hotkey(keyCode: 0x60, modifiers: [.control, .option])
            let data = try JSONEncoder().encode(HotkeyOverrides([.bindCurrentChat: f5]))
            let decoded = try JSONDecoder().decode(HotkeyOverrides.self, from: data)
            c.expectEqual(decoded.hotkeys, [.bindCurrentChat: f5], "JSON туда и обратно")

            let json = """
            {"version": 1, "hotkeys": {
              "nextTask": {"keyCode": 10, "modifiers": ["control", "shift"]},
              "unknownAction": {"keyCode": 1, "modifiers": ["control"]},
              "previousTask": {"keyCode": "x"},
              "bindCurrentChat": {"keyCode": 2, "modifiers": ["hyper"]}
            }}
            """
            let lossy = try JSONDecoder().decode(HotkeyOverrides.self, from: Data(json.utf8))
            c.expectEqual(lossy.hotkeys, [.nextTask: Hotkey(keyCode: section, modifiers: [.control, .shift])],
                          "неизвестные действия и битые записи пропускаются")
            // Старый hotkeys.json без «сделано»: загружается, у «сделано» остаётся умолчание.
            let old = try JSONDecoder().decode(HotkeyOverrides.self, from: Data("""
                {"version": 1, "hotkeys": {"nextTask": {"keyCode": 96, "modifiers": ["control"]}}}
                """.utf8))
            let oldResolved = HotkeyAssignments.resolve(overrides: old, defaults: HotkeyAssignments.defaults(for: .iso))
            c.expectEqual(oldResolved[.toggleDone], Hotkey(keyCode: 2, modifiers: [.control, .option]), "старый файл: «сделано» — по умолчанию")
            let ownDone = Hotkey(keyCode: 0x60, modifiers: [.control, .option])
            let doneData = try JSONEncoder().encode(HotkeyOverrides([.toggleDone: ownDone]))
            c.expect(String(decoding: doneData, as: UTF8.self).contains("\"toggleDone\""), "ключ в hotkeys.json — toggleDone")
            c.expectEqual(try JSONDecoder().decode(HotkeyOverrides.self, from: doneData).hotkeys, [.toggleDone: ownDone], "переназначение «сделано» сохраняется")
            let empty = try JSONDecoder().decode(HotkeyOverrides.self, from: Data("{}".utf8))
            c.expect(empty.hotkeys.isEmpty, "пустой объект — без своих сочетаний")

            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("juggler-switch-checks-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = HotkeyOverridesStore(fileURL: dir.appendingPathComponent("sub/hotkeys.json"))
            c.expectEqual(store.load().outcome, .missing, "нет файла → умолчания")
            try store.save(HotkeyOverrides([.nextTask: f5]))
            let loaded = store.load()
            c.expectEqual(loaded.outcome, .loaded, "файл записан и прочитан")
            c.expectEqual(loaded.overrides.hotkeys[.nextTask], f5, "сочетание пережило перезапуск")
            try Data("не json".utf8).write(to: store.fileURL)
            let corrupt = store.load()
            if case .corrupt = corrupt.outcome { c.expect(true, "битый файл распознан") } else { c.expect(false, "битый файл распознан") }
            c.expect(corrupt.overrides.hotkeys.isEmpty, "битый файл → умолчания")
            c.expectEqual(HotkeyOverridesStore.defaultFileURL.lastPathComponent, "hotkeys.json", "файл по умолчанию")
            c.expectEqual(
                HotkeyOverridesStore.defaultFileURL.deletingLastPathComponent(),
                TaskStore.defaultFileURL.deletingLastPathComponent(), "рядом с tasks.json")
        }
    }

    static func plannerChecks(_ c: CheckRunner) {
        c.group("выбор задачи при переключении") {
            let chrome = JugglerTask(title: "Chrome", binding: .chromeTab(ChromeTabRef(tabID: 7, url: "https://a.example/x", title: "A")))
            let done = JugglerTask(title: "Сделано", isDone: true, binding: .appWindow(AppWindowRef(bundleID: "com.x.done")))
            let claude = JugglerTask(title: "Claude", binding: .claudeChat(ClaudeChatRef(conversationID: "0f8fad5b-d9cb-469f-a165-70867728950e")))
            let plain = JugglerTask(title: "Без привязки")
            let doc = TasksDocument(tasks: [chrome, done, claude, plain], lastActiveTaskID: plain.id)
            let chromeCtx = FrontmostContext(bundleID: KnownBundleIDs.chrome, chromeTab: ChromeTabRef(tabID: 7, url: "https://a.example/x"))
            let claudeCtx = FrontmostContext(bundleID: KnownBundleIDs.claude, claudeConversationID: "0F8FAD5B-D9CB-469F-A165-70867728950E")

            c.expectEqual(SwitchPlanner.currentTaskID(context: chromeCtx, document: doc), chrome.id, "текущая — по переднему окну")
            c.expectEqual(SwitchPlanner.target(direction: .next, context: chromeCtx, document: doc), claude.id, "вперёд, «сделано» пропущена")
            c.expectEqual(SwitchPlanner.target(direction: .previous, context: claudeCtx, document: doc), chrome.id, "назад, «сделано» пропущена")
            c.expectEqual(SwitchPlanner.target(direction: .next, context: claudeCtx, document: doc), plain.id, "вперёд к задаче без привязки")
            c.expectEqual(SwitchPlanner.target(direction: .next, context: .unknown, document: doc), chrome.id,
                          "окно не узнано → от последней активной, по кругу")
            c.expectEqual(SwitchPlanner.target(direction: .previous, context: chromeCtx, document: doc), plain.id, "назад с первой — на последнюю")

            let fresh = TasksDocument(tasks: [chrome, done, claude])
            c.expectEqual(SwitchPlanner.target(direction: .next, context: .unknown, document: fresh), chrome.id, "без истории: следующая — первая")
            c.expectEqual(SwitchPlanner.target(direction: .previous, context: .unknown, document: fresh), claude.id, "без истории: предыдущая — последняя")
            c.expectNil(SwitchPlanner.target(direction: .next, context: chromeCtx, document: TasksDocument()), "пустой список → некуда")
            c.expectNil(SwitchPlanner.target(direction: .next, context: .unknown, document: TasksDocument(tasks: [done])), "все «сделано» → некуда")

            // Передняя вкладка совпала со «сделано» — отсчёт всё равно от неё.
            let doneTab = JugglerTask(title: "Готово", isDone: true, binding: .chromeTab(ChromeTabRef(tabID: 9, url: "https://b.example")))
            let doc2 = TasksDocument(tasks: [chrome, doneTab, claude])
            let doneCtx = FrontmostContext(bundleID: KnownBundleIDs.chrome, chromeTab: ChromeTabRef(tabID: 9, url: "https://b.example"))
            c.expectEqual(SwitchPlanner.target(direction: .next, context: doneCtx, document: doc2), claude.id, "из сделанной — к следующей несделанной")
        }
    }

    static func cardChecks(_ c: CheckRunner) {
        c.group("карточка перехода") {
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let bound = JugglerTask(
                title: "  План   релиза ", note: "  зачем: успеть к пятнице\n\n  дальше: тесты  ",
                lastVisitedAt: now.addingTimeInterval(-7 * 60 - 30),
                binding: .claudeChat(ClaudeChatRef(conversationID: "0f8fad5b-d9cb-469f-a165-70867728950e")))
            let unbound = JugglerTask(title: "", lastVisitedAt: nil)
            let doc = TasksDocument(tasks: [bound, unbound])
            let bindKey = Hotkey(keyCode: section, modifiers: [.control, .option])

            let card = TransitionCardBuilder.content(for: bound.id, in: doc, now: now, bindHotkey: bindKey, activation: .activated)
            c.expectEqual(card?.number, 1, "номер — позиция в списке")
            c.expectEqual(card?.title, "План релиза", "лишние пробелы в названии схлопнуты")
            c.expectEqual(card?.note, "зачем: успеть к пятнице\nдальше: тесты", "заметка без пустых строк и краевых пробелов")
            c.expectEqual(card?.absenceText, "не был 7 мин", "«не был N мин» до обновления захода")
            c.expectEqual(card?.staleness, .fresh, "уровень старения")
            c.expectEqual(card?.source, .claudeChat, "значок источника")
            c.expectNil(card?.hint ?? nil, "с привязкой и успешной активацией — без подсказки")
            c.expectEqual(card.map(TransitionCardBuilder.headline), "1. План релиза", "заголовок карточки")

            let free = TransitionCardBuilder.content(for: unbound.id, in: doc, now: now, bindHotkey: bindKey)
            c.expectEqual(free?.number, 2, "вторая задача")
            c.expectEqual(free?.title, "Без названия", "пустое название")
            c.expectEqual(free?.absenceText, "ещё не был", "ни разу не открывалась")
            c.expectEqual(free?.staleness, .never, "уровень «никогда»")
            c.expectEqual(free?.hint, "Нет привязки: откройте чат и нажмите ⌃⌥§", "подсказка с текущим хоткеем привязки")
            c.expectEqual(
                TransitionCardBuilder.content(for: unbound.id, in: doc, now: now, bindHotkey: nil)?.hint,
                "Нет привязки: откройте чат и выберите в меню «Добавить текущее окно»",
                "хоткей не назначен — подсказка про меню")
            c.expectEqual(
                TransitionCardBuilder.content(for: unbound.id, in: doc, now: now,
                                              bindHotkey: Hotkey(keyCode: grave, modifiers: [.control, .option]))?.hint,
                "Нет привязки: откройте чат и нажмите ⌃⌥`", "ANSI-клавиатура")

            c.expectEqual(
                TransitionCardBuilder.hint(hasBinding: true, bindHotkey: bindKey, activation: .failed("Chrome не отвечает")),
                "Не удалось открыть: Chrome не отвечает", "ошибка активации")
            c.expectEqual(
                TransitionCardBuilder.hint(hasBinding: true, bindHotkey: bindKey, activation: .failed("  ")),
                "Не удалось открыть привязку", "ошибка без текста")
            c.expectEqual(
                TransitionCardBuilder.hint(hasBinding: true, bindHotkey: bindKey, activation: .fallback("Вкладка открыта заново")),
                "Вкладка открыта заново", "запасной вариант активации")
            c.expectNil(TransitionCardBuilder.hint(hasBinding: true, bindHotkey: nil, activation: nil) ?? nil, "без активации — без подсказки")
            c.expectNil(TransitionCardBuilder.content(for: UUID(), in: doc, now: now, bindHotkey: bindKey), "нет такой задачи")

            let long = String(repeating: "а", count: 500)
            let note = TransitionCardBuilder.note(long)
            c.expect(note.count == TransitionCardBuilder.maxNoteLength && note.hasSuffix("…"), "длинная заметка обрезается с «…»")
            c.expectEqual(TransitionCardBuilder.title(String(repeating: "б", count: 300)).count, TransitionCardBuilder.maxTitleLength, "длинное название обрезается")

            let timing = CardTiming.standard
            c.expect((1.0...1.5).contains(timing.total), "карточка видна 1–1,5 с (\(timing.total))")
            c.expect(timing.fadeOut > 0 && timing.fadeIn >= 0, "исчезает плавно")
        }
    }
}
