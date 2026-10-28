import AppKit
import Combine
import Foundation
import JugglerCore
import ServiceManagement

/// Самопроверка UI: логика списка, сохранение через `AppModel` и перезапуск,
/// значки меню-бара, чтение статуса запуска при входе. Окон не показывает,
/// разрешений не запрашивает, запуск при входе не меняет.
@MainActor
enum UISelfTest {
    static func run() -> [SelfTestResult] {
        [listOperations(), persistenceAcrossRestart(), menuBarSymbols(), loginItemStatus(), languageSelection()]
    }

    private static func listOperations() -> SelfTestResult {
        var doc = TasksDocument()
        let now = Date()
        let a = TaskListOps.add(&doc, title: "Первая", now: now)
        let b = TaskListOps.add(&doc, title: "", now: now)
        TaskListOps.rename(&doc, id: b, to: "Вторая")
        TaskListOps.move(&doc, id: b, by: -1)
        TaskListOps.toggleDone(&doc, id: a)
        doc.markVisited(b, at: now)
        let rows = TaskListPresenter.rows(for: doc, now: now)
        let ok = rows.map(\.title) == ["Вторая", "Первая"] && rows[0].isCurrent && rows[1].isDone
        return SelfTestResult("UI: операции со списком", passed: ok)
    }

    private static func persistenceAcrossRestart() -> SelfTestResult {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("juggler-ui-self-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskStore(fileURL: dir.appendingPathComponent("tasks.json"))

        let first = AppModel(store: store)
        first.load()
        var ids: [UUID] = []
        first.update { doc in
            ids.append(TaskListOps.add(&doc, title: "Один", now: Date()))
            ids.append(TaskListOps.add(&doc, title: "Два", now: Date()))
        }
        first.update { doc in
            TaskListOps.setNote(&doc, id: ids[0], to: "дальше: ответить")
            TaskListOps.setDone(&doc, id: ids[1], true)
            TaskListOps.move(&doc, fromOffsets: IndexSet(integer: 1), toOffset: 0)
        }

        let second = AppModel(store: store)
        second.load()
        let tasks = second.tasks
        let ok = second.loadOutcome == .loaded
            && tasks.map(\.id) == [ids[1], ids[0]]
            && tasks.first?.isDone == true
            && tasks.last?.note == "дальше: ответить"
            && first.lastSaveError == nil
        return SelfTestResult("UI: изменения списка переживают перезапуск", passed: ok,
                              detail: ok ? "" : "получено \(tasks.map(\.title))")
    }

    private static func menuBarSymbols() -> SelfTestResult {
        let appearances: [MenuBarDot.Appearance] = [.outline] + MenuBarDotColor.allCases.map { .filled($0) }
        let images = appearances.map { MenuBarDotImage.image(for: $0) }
        // Серый контур — шаблон (красится системой), цветные кружки — нет (иначе потеряют цвет).
        let ok = images.first?.isTemplate == true
            && images.dropFirst().allSatisfy { !$0.isTemplate && $0.size.width > 0 }
        return SelfTestResult("UI: кружок меню-бара рисуется (контур — шаблон, цветные — нет)", passed: ok,
                              detail: ok ? "" : "признаки шаблона: \(images.map(\.isTemplate))")
    }

    private static func loginItemStatus() -> SelfTestResult {
        let state = LoginItemController.map(SMAppService.mainApp.status)
        return SelfTestResult("UI: статус запуска при входе читается", passed: true, detail: state.rawValue)
    }

    /// Выбор языка на временном домене настроек и отдельном переводчике: настоящий `com.sefimov.juggler`
    /// и язык приложения не затрагиваются. Тексты переключаются сразу, без перезапуска.
    private static func languageSelection() -> SelfTestResult {
        let suite = "com.sefimov.juggler.self-test.language.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return SelfTestResult("UI: выбор языка", passed: false, detail: "нет временного домена настроек")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let realBefore = LanguageSettings.app.storedOverride
        let localizer = Localizer(resourcesURL: Localizer.shared.resourcesURL, language: "ru")
        let controller = LanguageController(
            settings: LanguageSettings(defaults: defaults, domain: suite),
            localizer: localizer,
            systemLanguages: { ["de-DE"] })
        var published = 0
        let subscription = controller.objectWillChange.sink { published += 1 }
        defer { subscription.cancel() }
        let hasTables = localizer.resourcesURL != nil

        let start = controller.choice == .system && !controller.needsRestart
            && controller.language == "de" && localizer.language == "de"
            && (!hasTables || localizer.string("Выйти") == "Beenden")
        controller.select(.language("ja"))
        let changed = controller.needsRestart && published > 0
            && defaults.persistentDomain(forName: suite)?[LanguageSettings.key] as? [String] == ["ja"]
            && controller.language == "ja"
            && (!hasTables || localizer.string("Выйти") == "終了")
        controller.select(.system)
        let reset = !controller.needsRestart && defaults.persistentDomain(forName: suite)?[LanguageSettings.key] == nil
            && controller.language == "de"
            && (!hasTables || (localizer.string("Выйти") == "Beenden" && localizer.plural("summary.tasks", 2) == "2 Aufgaben"))
        let untouched = LanguageSettings.app.storedOverride == realBefore
        let expected = LanguageSettings.app.effectiveLanguage(systemPreferred: LanguageSettings.systemPreferredLanguages())
        let sharedOK = Localizer.shared.language == expected
        let ok = start && changed && reset && untouched && sharedOK && AppLanguage.all.count == 12
        let detail = "язык приложения \(Localizer.shared.language), таблицы \(hasTables ? "есть" : "нет"); временный домен, настоящие настройки не тронуты"
        return SelfTestResult("UI: выбор языка и смена без перезапуска", passed: ok,
                              detail: ok ? detail : "start \(start) changed \(changed) reset \(reset) untouched \(untouched) shared \(sharedOK)")
    }
}
