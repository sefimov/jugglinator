import Foundation
import JugglerCore

// Проверки ядра (задача CORE). Разнесены по файлам этой папки через extension CoreChecks.

enum CoreChecks: CheckSuite {
    static let name = "Core"

    static func run(_ c: CheckRunner) {
        modelChecks(c)
        storeChecks(c)
        cyclerChecks(c)
        resolverChecks(c)
        stalenessChecks(c)
        linkChecks(c)
        titleChecks(c)
        sessionChecks(c)
        toggleChecks(c)
    }
}

// MARK: - Общие помощники

enum Fixture {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    static func task(_ title: String, done: Bool = false, binding: TaskBinding? = nil) -> JugglerTask {
        JugglerTask(title: title, isDone: done, createdAt: t0, binding: binding)
    }

    static func tempStore() -> (TaskStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("juggler-checks-\(UUID().uuidString)", isDirectory: true)
        return (TaskStore(fileURL: dir.appendingPathComponent("tasks.json"), now: { t0 }), dir)
    }
}
