import Foundation
import JugglerCore

// Language switch without relaunch (LIVELANG): loc(...) keys, reading <lang>.lproj tables directly,
// switching on the fly, fallback translation for a missing key, plurals from .stringsdict,
// "Same as system" from the system languages. Tables come from the repo's Localization/.

extension UIChecks {
    /// The repo's `Localization/` (four levels up from this file Sources/JugglerChecks/UI/…).
    static let repoLocalization = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Localization", isDirectory: true)

    /// Run `body` with the shared translator set to `code`, then restore the previous language.
    static func withSharedLanguage<T>(_ code: String, _ body: () -> T) -> T {
        let previous = Localizer.shared.language
        Localizer.shared.setLanguage(code)
        defer { Localizer.shared.setLanguage(previous) }
        return body()
    }

    static func checkLiveLanguage(_ c: CheckRunner) {
        c.group("loc: ключи как у String(localized:)") {
            let n = 3
            let code: Int32 = -9878
            let title = "Почта"
            let plain: LocalizedText = "Выйти"
            c.expectEqual(plain.key, "Выйти", "литерал без интерполяций — ключ как есть")
            c.expect(plain.arguments.isEmpty, "без аргументов")
            let mixed: LocalizedText = "Задача \(n) «\(title)» сделана"
            c.expectEqual(mixed.key, "Задача %lld «%@» сделана", "Int → %lld, String → %@")
            c.expectEqual(mixed.arguments.count, 2, "два аргумента")
            let status: LocalizedText = "Не удалось зарегистрировать (код \(code))."
            c.expectEqual(status.key, "Не удалось зарегистрировать (код %d).", "Int32 → %d")
            let other: LocalizedText = "Значение \(2.5)"
            c.expectEqual(other.key, "Значение %@", "прочие типы → %@")
            let percent: LocalizedText = "\(n)% готово"
            c.expectEqual(percent.key, "%lld%% готово", "«%» в тексте с интерполяцией экранируется")
        }

        c.group("Localizer: таблицы <язык>.lproj") {
            let localizer = Localizer(resourcesURL: repoLocalization, language: "en")
            c.expect(AppLanguage.all.allSatisfy { localizer.hasTable(for: $0.code) }, "таблица есть для всех 12 языков")
            c.expect(!localizer.hasTable(for: "nl"), "таблицы нидерландского нет")
            c.expectEqual(localizer.string("Выйти"), "Quit", "en: «Выйти» → Quit")
            c.expectEqual(localizer.string("Задача \(1) «\("X")» сделана"), "Task 1 “X” done", "en: подстановка значений")
            localizer.setLanguage("de")
            c.expectEqual(localizer.string("Выйти"), "Beenden", "смена языка на ходу: de")
            localizer.setLanguage("ja")
            c.expectEqual(localizer.string("Выйти"), "終了", "смена языка на ходу: ja")
            localizer.setLanguage("ru")
            c.expectEqual(localizer.string("Выйти"), "Выйти", "ru — сам ключ")
            c.expect(!localizer.setLanguage("ru"), "тот же язык — без изменения")
            c.expect(localizer.setLanguage("ar"), "другой язык — изменение")
            c.expectEqual(localizer.string("Выйти"), "خروج", "ar")
            c.expectEqual(localizer.locale.identifier, "ar", "локаль выбранного языка")
        }

        c.group("Localizer: отсутствующий ключ") {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("jugglinator-livelang-checks-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            func table(_ code: String, _ text: String) throws {
                let lproj = dir.appendingPathComponent("\(code).lproj", isDirectory: true)
                try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
                try text.write(to: lproj.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
            }
            try table("en", "\"Один\" = \"One\";\n\"Два\" = \"Two\";\n\"Задача %lld\" = \"Task %lld\";\n")
            try table("de", "\"Один\" = \"Eins\";\n")
            let localizer = Localizer(resourcesURL: dir, language: "de")
            c.expectEqual(localizer.string("Один"), "Eins", "есть в выбранном языке")
            c.expectEqual(localizer.string("Два"), "Two", "нет в de — из английского (язык разработки)")
            c.expectEqual(localizer.string("Задача \(7)"), "Task 7", "запасной перевод с подстановкой")
            c.expectEqual(localizer.string("Три"), "Три", "нет нигде — сам ключ")
            c.expectEqual(localizer.string("Нет \(5) штук"), "Нет 5 штук", "ключ с подстановкой, если перевода нет")
            c.expectNil(localizer.translation(forKey: "Три"), "translation: nil, если ключа нет")
            localizer.setLanguage("fr")
            c.expectEqual(localizer.string("Один"), "One", "нет таблицы языка — английский")
            localizer.setLanguage("ru")
            c.expectEqual(localizer.string("Два"), "Два", "ru: английский не подставляется, ключ уже русский")
            c.expectEqual(localizer.lookupOrder(for: "de"), ["de", "en"], "порядок поиска de → en")
            c.expectEqual(localizer.lookupOrder(for: "ru"), ["ru"], "порядок поиска ru")
            let none = Localizer(resourcesURL: nil, language: "de")
            c.expectEqual(none.string("Задача \(2)"), "Задача 2", "без таблиц (swift run без Localization) — ключ")
            c.expectNil(none.plural("summary.tasks", 2), "без таблиц склонений нет")
        }

        c.group("Localizer: склонения из .stringsdict") {
            let localizer = Localizer(resourcesURL: repoLocalization, language: "ru")
            func forms(_ key: String, _ code: String, _ numbers: [Int]) -> [String] {
                localizer.setLanguage(code)
                return numbers.map { localizer.plural(key, $0) ?? "nil" }
            }
            c.expectEqual(forms("summary.tasks", "ru", [1, 2, 5, 11, 21, 102]),
                          ["1 задача", "2 задачи", "5 задач", "11 задач", "21 задача", "102 задачи"], "ru: задача/задачи/задач")
            c.expectEqual(forms("summary.done", "ru", [1, 3, 5]), ["1 сделана", "3 сделаны", "5 сделано"], "ru: сделана/сделаны/сделано")
            c.expectEqual(forms("summary.tasks", "en", [1, 2]), ["1 task", "2 tasks"], "en: task/tasks")
            c.expectEqual(forms("clearAll.confirm", "en", [1, 5]), ["Delete 1 task?", "Delete all 5 tasks?"], "en: вопрос об очистке")
            c.expectEqual(forms("clearAll.confirm", "de", [1, 5]), ["1 Aufgabe löschen?", "Alle 5 Aufgaben löschen?"], "de: вопрос об очистке")
            c.expectEqual(forms("clearDone.confirm", "en", [1, 3]), ["Delete 1 done task?", "Delete 3 done tasks?"], "en: вопрос об удалении сделанных")
            c.expectEqual(forms("clearDone.confirm", "ru", [1, 3, 5]),
                          ["Удалить 1 сделанную задачу?", "Удалить 3 сделанные задачи?", "Удалить 5 сделанных задач?"], "ru: сделанную/сделанные/сделанных")
            c.expectEqual(forms("summary.tasks", "ar", [1, 2, 3]), ["مهمة واحدة", "مهمتان", "3 مهام"], "ar: формы one/two/few")
            c.expectEqual(forms("clearAll.confirm", "ru", [1, 21, 3]), ["Удалить 1 задачу?", "Удалить 21 задачу?", "Удалить все 3 задачи?"],
                          "ru: правила языка таблицы, а не системы")
            c.expectNil(localizer.plural("нет.такого", 1), "нет ключа — nil")
        }

        c.group("Тексты Jugglinator на выбранном сейчас языке") {
            var doc = TasksDocument()
            let a = TaskListOps.add(&doc, title: "Почта", now: t0)
            _ = TaskListOps.add(&doc, title: "", now: t0)
            doc.markVisited(a, at: t0)
            let now = t0.addingTimeInterval(5 * 60)
            let space = Hotkey(keyCode: 0x31, modifiers: [.control, .option])

            let en = withSharedLanguage("en") {
                (TaskToggleTexts.quitMenuTitle,
                 TaskListPresenter.summary(for: doc),
                 TaskListPresenter.clearAllConfirmation(count: 2),
                 Staleness.absenceText(lastVisited: t0, now: now),
                 DoneToggleTexts.card(number: 1, title: "Почта", isDone: true),
                 KeyCode.displayName(0x31),
                 MenuBarDotPresenter.dot(for: doc, now: now).tooltip,
                 TaskToggleTexts.removedCard(number: 1, title: "Почта", hotkey: space))
            }
            c.expectEqual(en.0, "Quit", "en: пункт меню")
            c.expectEqual(en.1, "2 tasks", "en: сводка (склонение)")
            c.expectEqual(en.2, "Delete all 2 tasks?", "en: вопрос об очистке")
            c.expectEqual(en.3, "away 5 min", "en: давность")
            c.expectEqual(en.4, "Task 1 “Почта” done", "en: карточка «сделано»")
            c.expectEqual(en.5, "Space", "en: подпись клавиши в хоткее")
            c.expect(en.6.hasPrefix("Jugglinator: task 2 has waited longest"), "en: подсказка кружка — \(en.6)")
            c.expect(!en.7.contains("Задача") && en.7.contains("⌃⌥Space"), "en: карточка удаления — \(en.7)")

            let de = withSharedLanguage("de") {
                (TaskToggleTexts.quitMenuTitle, KeyCode.displayName(0x31), Staleness.absenceText(lastVisited: t0, now: now))
            }
            c.expectEqual(de.0, "Beenden", "смена en → de без перезапуска: меню")
            c.expectEqual(de.1, "Leertaste", "смена en → de: клавиша (не закэширована)")
            c.expectEqual(de.2, "5 Min. weg", "смена en → de: давность")

            c.expectEqual(TaskToggleTexts.quitMenuTitle, "Выйти", "после проверки снова русский")
            c.expectEqual(TaskListPresenter.summary(for: doc), "2 задачи", "русская сводка из ru.lproj")
        }

        c.group("Язык: «Как в системе» и выбранный") {
            c.expectEqual(LanguageSettings.code(for: .system, systemPreferred: ["de-AT", "en"]), "de", "система de-AT → de")
            c.expectEqual(LanguageSettings.code(for: .system, systemPreferred: ["nl-NL"]), "en", "нет перевода языка системы — en")
            c.expectEqual(LanguageSettings.code(for: .system, systemPreferred: []), "en", "пустой список — en")
            c.expectEqual(LanguageSettings.code(for: .language("ko"), systemPreferred: ["de"]), "ko", "выбранный язык важнее системы")

            let suite = "com.sefimov.jugglinator.checks.livelang.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suite) else {
                c.expect(false, "не удалось создать домен настроек для проверок")
                return
            }
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = LanguageSettings(defaults: defaults, domain: suite)
            c.expectEqual(settings.effectiveLanguage(systemPreferred: ["fr-CA"]), "fr", "без значения — язык системы")
            settings.select(.language("ja"))
            c.expectEqual(settings.effectiveLanguage(systemPreferred: ["fr-CA"]), "ja", "выбран ja")
            settings.select(.system)
            c.expectEqual(settings.effectiveLanguage(systemPreferred: ["zh-Hans-CN"]), "zh-Hans", "снова как в системе")
            c.expect(!LanguageSettings.systemPreferredLanguages().isEmpty, "языки системы читаются")
        }

        c.group("Localizer: где искать таблицы") {
            c.expectEqual(Localizer.shared.resourcesURL?.standardizedFileURL.path, repoLocalization.standardizedFileURL.path,
                          "без .app — Localization/ репозитория рядом со сборкой")
        }
    }
}
