import Foundation
import JugglerCore

/// `Juggler --self-test`: инициализирует компоненты, не запрашивая разрешений
/// и не показывая окон. Код выхода 0 — всё прошло.
///
/// Каждый модуль добавляет свои проверки в `<Module>.selfTest()` в своей папке.
@MainActor
enum SelfTest {
    static func run() -> Int32 {
        var results = coreResults()
        results += BindModule.selfTest()
        results += SwitchModule.selfTest()
        results += UIModule.selfTest()

        for result in results {
            let mark = result.passed ? "ok  " : "FAIL"
            let detail = result.detail.isEmpty ? "" : " — \(result.detail)"
            print("[\(mark)] \(result.name)\(detail)")
        }
        let failed = results.filter { !$0.passed }.count
        print("Самопроверка: \(results.count - failed) из \(results.count) прошли")
        return failed == 0 ? 0 : 1
    }

    /// Хранилище и корень композиции на временном файле (настоящий tasks.json не трогается).
    private static func coreResults() -> [SelfTestResult] {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("juggler-self-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskStore(fileURL: dir.appendingPathComponent("tasks.json"))

        var results: [SelfTestResult] = []
        do {
            let task = JugglerTask(title: "Самопроверка")
            try store.save(TasksDocument(tasks: [task], lastActiveTaskID: task.id))
            let loaded = store.load()
            results.append(SelfTestResult(
                "Хранилище: запись и чтение",
                passed: loaded.outcome == .loaded && loaded.document.tasks.map(\.id) == [task.id]))
        } catch {
            results.append(SelfTestResult("Хранилище: запись и чтение", passed: false, detail: error.localizedDescription))
        }

        let env = AppEnvironment.makeLive(store: store)
        results.append(SelfTestResult(
            "Корень композиции собирается",
            passed: env.model.tasks.count == 1 && env.model.currentTaskNumber == 1))
        return results
    }
}
