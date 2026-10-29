import Foundation
import JugglerCore

// Checks of the one-time copy of data from the old app name (Juggler) to Jugglinator.

extension CoreChecks {
    static func migrationChecks(_ c: CheckRunner) {
        let fm = FileManager.default
        func tempRoot() -> URL {
            let url = fm.temporaryDirectory.appendingPathComponent("jugglinator-migration-\(UUID().uuidString)", isDirectory: true)
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        func write(_ text: String, to dir: URL, name: String) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try? text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        func read(_ dir: URL, _ name: String) -> String? {
            try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
        }

        c.group("Миграция: старой папки нет — ничего не делать") {
            let root = tempRoot(); defer { try? fm.removeItem(at: root) }
            let new = root.appendingPathComponent("Jugglinator", isDirectory: true)
            let legacy = LegacyDataMigration.legacyDirectory(for: new)
            c.expectEqual(legacy.lastPathComponent, "Juggler", "старая папка рядом с новой")
            c.expectEqual(LegacyDataMigration.migrateFiles(from: legacy, to: new), .nothingToDo, "исход")
            c.expect(!fm.fileExists(atPath: new.path), "новая папка не создана")
        }

        c.group("Миграция: tasks.json и hotkeys.json копируются, старые остаются") {
            let root = tempRoot(); defer { try? fm.removeItem(at: root) }
            let new = root.appendingPathComponent("Jugglinator", isDirectory: true)
            let legacy = LegacyDataMigration.legacyDirectory(for: new)
            write("{\"tasks\":[]}", to: legacy, name: "tasks.json")
            write("{\"hotkeys\":{}}", to: legacy, name: "hotkeys.json")
            write("sock", to: legacy, name: "mcp.sock")
            c.expectEqual(LegacyDataMigration.migrateFiles(from: legacy, to: new), .copied(["tasks.json", "hotkeys.json"]), "исход")
            c.expectEqual(read(new, "tasks.json"), "{\"tasks\":[]}", "tasks.json скопирован")
            c.expectEqual(read(new, "hotkeys.json"), "{\"hotkeys\":{}}", "hotkeys.json скопирован")
            c.expect(!fm.fileExists(atPath: new.appendingPathComponent("mcp.sock").path), "mcp.sock не копируется")
            c.expectEqual(read(legacy, "tasks.json"), "{\"tasks\":[]}", "старый tasks.json на месте")
        }

        c.group("Миграция: новая папка уже с данными — ничего не перезаписывать") {
            let root = tempRoot(); defer { try? fm.removeItem(at: root) }
            let new = root.appendingPathComponent("Jugglinator", isDirectory: true)
            let legacy = LegacyDataMigration.legacyDirectory(for: new)
            write("old", to: legacy, name: "tasks.json")
            write("old", to: legacy, name: "hotkeys.json")
            write("new", to: new, name: "tasks.json")
            c.expectEqual(LegacyDataMigration.migrateFiles(from: legacy, to: new), .alreadyMigrated, "исход")
            c.expectEqual(read(new, "tasks.json"), "new", "tasks.json не тронут")
            c.expect(!fm.fileExists(atPath: new.appendingPathComponent("hotkeys.json").path), "hotkeys.json не докопирован")
        }

        c.group("Миграция: выбор языка копируется из старого домена один раз") {
            let defaults = UserDefaults.standard
            let suffix = UUID().uuidString
            let legacy = "com.sefimov.jugglinator.check.legacy.\(suffix)"
            let domain = "com.sefimov.jugglinator.check.new.\(suffix)"
            defer { defaults.removePersistentDomain(forName: legacy); defaults.removePersistentDomain(forName: domain) }
            c.expect(!LegacyDataMigration.migrateLanguage(defaults: defaults, legacyDomain: legacy, domain: domain), "пусто — нечего копировать")
            defaults.setPersistentDomain([LanguageSettings.key: ["de"]], forName: legacy)
            c.expect(LegacyDataMigration.migrateLanguage(defaults: defaults, legacyDomain: legacy, domain: domain), "скопировано")
            c.expectEqual(defaults.persistentDomain(forName: domain)?[LanguageSettings.key] as? [String], ["de"], "значение в новом домене")
            defaults.setPersistentDomain([LanguageSettings.key: ["fr"]], forName: domain)
            c.expect(!LegacyDataMigration.migrateLanguage(defaults: defaults, legacyDomain: legacy, domain: domain), "новое значение не перезаписывается")
            c.expectEqual(defaults.persistentDomain(forName: domain)?[LanguageSettings.key] as? [String], ["fr"], "fr остался")
        }
    }
}
