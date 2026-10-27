import Foundation
import JugglerCore

extension CoreChecks {
    static func stalenessChecks(_ c: CheckRunner) {
        c.group("«не был N мин» и старение") {
            let now = Fixture.t0
            func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }
            func text(_ date: Date?) -> String { Staleness.absenceText(lastVisited: date, now: now) }
            func level(_ date: Date?) -> StalenessLevel { Staleness.level(lastVisited: date, now: now) }

            c.expectEqual(text(nil), "ещё не был", "без захода")
            c.expectEqual(text(ago(59)), "был только что", "меньше минуты")
            c.expectEqual(text(ago(60)), "не был 1 мин", "ровно минута")
            c.expectEqual(text(ago(7 * 60 + 59)), "не был 7 мин", "минуты округляются вниз")
            c.expectEqual(text(ago(120 * 60)), "не был 2 ч", "ровные часы")
            c.expectEqual(text(ago(65 * 60)), "не был 1 ч 5 мин", "часы и минуты")
            c.expectEqual(text(ago(3 * 24 * 3600 + 100)), "не был 3 дн", "дни")
            c.expectEqual(text(now.addingTimeInterval(300)), "был только что", "время в будущем (сдвиг часов) → 0")
            c.expectEqual(Staleness.minutesSince(now.addingTimeInterval(300), now: now), 0, "minutesSince не бывает отрицательным")

            c.expectEqual(level(nil), .never, "уровень: без захода")
            c.expectEqual(level(ago(9 * 60 + 59)), .fresh, "уровень: 9:59 — свежая")
            c.expectEqual(level(ago(10 * 60)), .aging, "уровень: 10 мин — граница «пора вернуться»")
            c.expectEqual(level(ago(30 * 60)), .stale, "уровень: 30 мин — давно")
            c.expectEqual(level(ago(60 * 60)), .forgotten, "уровень: 60 мин — забыта")
            let custom = StalenessThresholds(agingMinutes: 1, staleMinutes: 2, forgottenMinutes: 3)
            c.expectEqual(Staleness.level(lastVisited: ago(150), now: now, thresholds: custom), .stale, "свои пороги")
        }
    }

    static func linkChecks(_ c: CheckRunner) {
        c.group("разбор ссылок") {
            let uuid = "0f8fad5b-d9cb-469f-a165-70867728950e"
            let claude = ChatLink.claude(conversationID: uuid)
            func parse(_ s: String) -> ChatLink? { ChatLinkParser.parse(s) }

            c.expectEqual(parse("https://claude.ai/chat/\(uuid)"), claude, "https://claude.ai/chat/<uuid>")
            c.expectEqual(parse("claude.ai/chat/\(uuid.uppercased())/"), claude, "без схемы, верхний регистр, хвостовой /")
            c.expectEqual(parse("https://www.claude.ai/chat/\(uuid)?foo=1#x"), claude, "www, query и fragment")
            c.expectEqual(parse("claude://claude.ai/chat/\(uuid)"), claude, "claude://claude.ai/chat/<uuid>")
            c.expectEqual(parse("claude://chat/\(uuid)"), claude, "claude://chat/<uuid>")
            c.expectEqual(parse("  \(uuid.uppercased())\n"), claude, "голый UUID с пробелами")
            c.expectEqual(parse("<https://claude.ai/chat/\(uuid)>"), claude, "ссылка в угловых скобках")
            c.expectEqual(parse("codex://threads/Th_42-a"), .chatGPT(threadID: "Th_42-a"), "codex://threads/<id>, регистр id сохраняется")
            c.expectEqual(parse("codex://threads/abc/"), .chatGPT(threadID: "abc"), "codex с хвостовым /")

            c.expectNil(parse(""), "пустая строка")
            c.expectNil(parse("https://claude.ai/chat/not-a-uuid"), "не UUID после /chat/")
            c.expectNil(parse("https://claude.ai/project/\(uuid)"), "проект Claude — не чат")
            c.expectNil(parse("https://evil.example/chat/\(uuid)"), "чужой хост")
            c.expectNil(parse("https://claude.ai.evil.example/chat/\(uuid)"), "хост, похожий на claude.ai")
            c.expectNil(parse("0f8fad5b-d9cb-469f-a165-70867728950"), "UUID короче нужного")
            c.expectNil(parse("codex://threads/"), "codex без id")
            c.expectNil(parse("codex://threads/a b"), "codex с пробелом в id")
            c.expectNil(parse("codex://projects/abc"), "codex не threads")
            c.expectNil(parse("ftp://claude.ai/chat/\(uuid)"), "чужая схема")

            c.expectEqual(claude.appURL.absoluteString, "claude://claude.ai/chat/\(uuid)", "ссылка для Claude desktop")
            c.expectEqual(ChatLink.chatGPT(threadID: "abc").appURL.absoluteString, "codex://threads/abc", "ссылка для ChatGPT desktop")
            c.expectEqual(URLNormalizer.normalize("HTTPS://Example.COM/a/b/#frag"), "https://example.com/a/b", "нормализация адреса")
            c.expectEqual(URLNormalizer.normalize("https://example.com/"), URLNormalizer.normalize("https://example.com"), "корень с / и без")
            c.expect(URLNormalizer.normalize("https://e.com/?q=1") != URLNormalizer.normalize("https://e.com/?q=2"), "query значим")
        }
    }

    static func titleChecks(_ c: CheckRunner) {
        c.group("очистка заголовков") {
            func clean(_ s: String) -> String { TitleCleaner.clean(s) }

            c.expectEqual(clean("План релиза - Claude"), "План релиза", "« - Claude»")
            c.expectEqual(clean("Код ревью — ChatGPT"), "Код ревью", "« — ChatGPT»")
            c.expectEqual(clean("Документ - Google Chrome"), "Документ", "« - Google Chrome»")
            c.expectEqual(clean("Чат - Claude - Google Chrome"), "Чат", "несколько хвостов подряд")
            c.expectEqual(clean("Почта - Google Chrome - Сергей"), "Почта", "хвост профиля Chrome")
            c.expectEqual(clean("(3) Входящие | Grok"), "Входящие", "счётчик непрочитанного и « | Grok»")
            c.expectEqual(clean("  много \n  пробелов  - claude "), "много пробелов", "пробелы, переводы строк, регистр хвоста")
            c.expectEqual(clean("Claude"), "", "только имя приложения → пусто")
            c.expectEqual(clean("Как работает Claude"), "Как работает Claude", "имя без разделителя не срезается")
            c.expectEqual(clean("A-Claude"), "A-Claude", "разделитель без пробелов не срезается")
            c.expectEqual(clean("x - y - Claude"), "x - y", "внутренние разделители сохраняются")
            c.expectEqual(clean("(1+)"), "(1+)", "один счётчик без текста не срезается в пустоту")

            c.expectEqual(TitleCleaner.suggestedTaskTitle(from: "Claude"), "Новая задача", "пустое название → «Новая задача»")
            c.expectEqual(TitleCleaner.suggestedTaskTitle(from: nil), "Новая задача", "нет заголовка → «Новая задача»")
            let long = TitleCleaner.suggestedTaskTitle(from: String(repeating: "я", count: 100) + " - Claude", maxLength: 10)
            c.expectEqual(long, String(repeating: "я", count: 9) + "…", "длинное название обрезается с «…»")
        }
    }
}
