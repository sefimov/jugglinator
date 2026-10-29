import Foundation
import JugglerCore

extension CoreChecks {
    static func storeChecks(_ c: CheckRunner) {
        let fm = FileManager.default

        c.group("хранилище: путь по умолчанию") {
            let path = TaskStore.defaultFileURL.path
            c.expect(path.hasSuffix("/Library/Application Support/Jugglinator/tasks.json"), "путь ~/Library/Application Support/Jugglinator/tasks.json")
        }

        c.group("хранилище: первый запуск и запись") {
            let (store, dir) = Fixture.tempStore()
            defer { try? fm.removeItem(at: dir) }

            let first = store.load()
            c.expectEqual(first.outcome, .missing, "нет файла → .missing")
            c.expect(first.document.tasks.isEmpty, "нет файла → пустой список")

            let a = Fixture.task("Первая")
            try store.save(TasksDocument(tasks: [a], lastActiveTaskID: a.id))
            c.expect(fm.fileExists(atPath: store.fileURL.path), "save создаёт каталог и файл")
            let loaded = store.load()
            c.expectEqual(loaded.outcome, .loaded, "после записи → .loaded")
            c.expectEqual(loaded.document.tasks, [a], "задачи читаются как записаны")

            let b = Fixture.task("Вторая")
            try store.save(TasksDocument(tasks: [a, b]))
            let backup = try TaskStore.decode(Data(contentsOf: store.backupURL))
            c.expectEqual(backup.tasks.map(\.id), [a.id], "перед записью предыдущая версия уходит в резервную копию")

            let leftovers = try fm.contentsOfDirectory(atPath: dir.path).filter { !$0.hasPrefix("tasks.") }
            c.expect(leftovers.isEmpty, "атомарная запись не оставляет временных файлов")
        }

        c.group("хранилище: битый файл с резервной копией") {
            let (store, dir) = Fixture.tempStore()
            defer { try? fm.removeItem(at: dir) }
            let a = Fixture.task("A"), b = Fixture.task("B")
            try store.save(TasksDocument(tasks: [a]))
            try store.save(TasksDocument(tasks: [a, b]))
            try Data("{\"tasks\": [ обрыв".utf8).write(to: store.fileURL)

            let result = store.load()
            guard case .recoveredFromBackup(let quarantined?) = result.outcome else {
                c.expect(false, "битый файл → .recoveredFromBackup, получено \(result.outcome)")
                return
            }
            c.expectEqual(result.document.tasks.map(\.id), [a.id], "данные восстановлены из резервной копии")
            c.expect(fm.fileExists(atPath: quarantined.path), "битый файл сохранён рядом для разбора")
            c.expect(quarantined.lastPathComponent.hasPrefix("tasks.corrupt-"), "имя карантина tasks.corrupt-<время>.json")
            c.expect(!fm.fileExists(atPath: store.fileURL.path), "битый основной файл убран с места")

            try store.save(result.document)
            c.expectEqual(store.load().outcome, .loaded, "после восстановления запись снова читается")
        }

        c.group("хранилище: битый файл без резервной копии") {
            let (store, dir) = Fixture.tempStore()
            defer { try? fm.removeItem(at: dir) }
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data().write(to: store.fileURL)
            let empty = store.load()
            guard case .resetAfterCorruption(_?) = empty.outcome else {
                c.expect(false, "пустой файл → .resetAfterCorruption, получено \(empty.outcome)")
                return
            }
            c.expect(empty.document.tasks.isEmpty, "пустой файл → пустой список")

            try Data("[1, 2, 3]".utf8).write(to: store.fileURL)
            let foreign = store.load()
            c.expect(foreign.outcome.isRecovery, "чужой JSON (без tasks) считается битым")
            let quarantined = try fm.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("tasks.corrupt-") }
            c.expectEqual(quarantined.count, 2, "повторный карантин в ту же секунду не затирает предыдущий")
        }
    }
}
