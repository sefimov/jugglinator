import Foundation
import JugglerCore

// Language choice: the list, language detection from AppleLanguages, writing and clearing the value
// in a separate domain (the real com.sefimov.juggler defaults are untouched), the relaunch command.

extension UIChecks {
    static func checkLanguage(_ c: CheckRunner) {
        c.group("Язык: список") {
            let codes = AppLanguage.all.map(\.code)
            c.expectEqual(codes.count, 12, "12 языков")
            c.expectEqual(Set(codes).count, 12, "коды не повторяются")
            c.expectEqual(Set(codes), Set(["ru", "en", "de", "es", "fr", "it", "pt-BR", "ja", "ko", "zh-Hans", "ar", "hi"]),
                          "набор совпадает с локализацией")
            c.expectEqual(AppLanguage.named("ru")?.nativeName, "Русский", "ru — Русский")
            c.expectEqual(AppLanguage.named("en")?.nativeName, "English", "en — English")
            c.expectEqual(AppLanguage.named("de")?.nativeName, "Deutsch", "de — Deutsch")
            c.expect(AppLanguage.all.allSatisfy { !$0.nativeName.isEmpty }, "у каждого есть своё название")
            c.expectEqual(Set(AppLanguage.all.map(\.nativeName)).count, 12, "названия различаются")
            c.expectNil(AppLanguage.named("nl"), "нидерландского нет")
        }

        c.group("Язык: по списку AppleLanguages") {
            func lang(_ list: [String]) -> LanguageChoice { LanguageChoice.resolving(preferred: list) }
            c.expectEqual(lang(["de"]), .language("de"), "de")
            c.expectEqual(lang(["pt-BR"]), .language("pt-BR"), "pt-BR целиком")
            c.expectEqual(lang(["zh-Hans-CN"]), .language("zh-Hans"), "zh-Hans-CN → zh-Hans")
            c.expectEqual(lang(["de-AT"]), .language("de"), "de-AT → de")
            c.expectEqual(lang(["ru_RU"]), .language("ru"), "ru_RU → ru")
            c.expectEqual(lang(["pt-PT"]), .language("pt-BR"), "pt-PT → pt-BR")
            c.expectEqual(lang(["nl", "fr"]), .language("fr"), "первый поддерживаемый из списка")
            c.expectEqual(lang(["nl", "sv"]), .language("en"), "нет перевода — английский")
            c.expectEqual(lang(["EN"]), .language("en"), "регистр не важен")
        }

        c.group("Язык: хранение") {
            let suite = "com.sefimov.juggler.checks.language.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suite) else {
                c.expect(false, "не удалось создать домен настроек для проверок")
                return
            }
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = LanguageSettings(defaults: defaults, domain: suite)

            c.expectEqual(settings.choice, .system, "по умолчанию «Как в системе»")
            c.expectNil(settings.storedOverride, "значения нет")

            settings.select(.language("de"))
            c.expectEqual(settings.storedOverride, ["de"], "записан AppleLanguages = [de]")
            c.expectEqual(settings.choice, .language("de"), "выбран de")

            settings.select(.language("zh-Hans"))
            c.expectEqual(settings.storedOverride, ["zh-Hans"], "смена языка заменяет значение")
            c.expectEqual(settings.choice, .language("zh-Hans"), "выбран zh-Hans")

            settings.select(.system)
            c.expectNil(settings.storedOverride, "«Как в системе» снимает значение")
            c.expectEqual(settings.choice, .system, "снова «Как в системе»")

            // A value not written by us (e.g. by the system's per-app "Language" setting).
            defaults.set(["ja-JP", "en-US"], forKey: LanguageSettings.key)
            c.expectEqual(settings.choice, .language("ja"), "чужое значение ja-JP читается как ja")
            defaults.set([String](), forKey: LanguageSettings.key)
            c.expectEqual(settings.choice, .system, "пустой список — как в системе")

            // Another domain doesn't see the chosen value.
            let other = "com.sefimov.juggler.checks.language.other.\(UUID().uuidString)"
            if let otherDefaults = UserDefaults(suiteName: other) {
                defer { otherDefaults.removePersistentDomain(forName: other) }
                settings.select(.language("fr"))
                c.expectEqual(LanguageSettings(defaults: otherDefaults, domain: other).choice, .system,
                              "значение лежит только в своём домене")
            }
        }

        c.group("Язык: перезапуск") {
            let command = AppRestart.relaunchCommand(bundlePath: "/Applications/Juggler.app", pid: 123)
            c.expectEqual(command?.executable, "/bin/sh", "через sh")
            c.expectEqual(command?.arguments.suffix(2).map { $0 }, ["/Applications/Juggler.app", "123"],
                          "путь и pid передаются аргументами, а не в тексте скрипта")
            c.expect(command?.arguments.dropFirst().first?.contains("open -n") == true, "открывает новый экземпляр")
            c.expect(command?.arguments.dropFirst().first?.contains("/Applications") == false, "путь не вшит в скрипт")
            let spaced = AppRestart.relaunchCommand(bundlePath: "/My Apps/Juggler \"x\".app", pid: 1)
            c.expectEqual(spaced?.arguments.dropLast().last, "/My Apps/Juggler \"x\".app", "пробелы и кавычки в пути не ломают команду")
            c.expectNil(AppRestart.relaunchCommand(bundlePath: "/work/juggler/.build/debug", pid: 1), "не из .app — перезапуска нет")
        }
    }
}
