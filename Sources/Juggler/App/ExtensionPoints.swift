import Foundation
import JugglerCore
import os

// Точки расширения приложения. Реализации живут в папках своих задач:
//   Sources/Juggler/Bind/   — BIND: контекст переднего окна, привязка, активация, разрешения;
//   Sources/Juggler/Switch/ — SWITCH: переключатель, карточка перехода, хоткеи;
//   Sources/Juggler/UI/     — UI: сцены меню-бара и окна настроек.
// Корень композиции (CompositionRoot.swift) получает реализации только через
// фабрики `BindModule`, `SwitchModule`, `UIModule` — их сигнатуры и есть контракт.
// Всё взаимодействие идёт на главном потоке (@MainActor).

// MARK: - BIND

/// Читает контекст переднего окна (bundle id, заголовок, вкладка Chrome, id чата).
/// Не должен падать и не должен показывать системные запросы: без разрешений
/// просто возвращает то, что удалось узнать.
@MainActor
protocol FrontmostContextProviding: AnyObject {
    func currentContext() -> FrontmostContext
}

/// Строит привязку по контексту переднего окна (без диалогов).
@MainActor
protocol BindingCapturing: AnyObject {
    func captureBinding(from context: FrontmostContext) -> BindingCaptureResult
}

/// Открывает привязанную вкладку, чат или окно; при необходимости запускает приложение.
@MainActor
protocol BindingActivating: AnyObject {
    func activate(_ binding: TaskBinding) -> ActivationResult
}

/// Разрешения Accessibility и Automation.
@MainActor
protocol PermissionsProviding: AnyObject {
    /// Выдано ли приложению разрешение Accessibility (без запроса).
    var isAccessibilityTrusted: Bool { get }
    /// Показать пользователю понятный запрос Accessibility.
    func requestAccessibility()
}

/// Сценарий «Сделать задачей текущий чат»: захват привязки,
/// при необходимости запрос ссылки, создание задачи или привязка к текущей задаче.
@MainActor
protocol CurrentChatBinding: AnyObject {
    func bindCurrentChat()
    /// ⌃⌥§ и «Добавить или удалить текущее окно» (D15): в окне отмены — вернуть
    /// удалённую задачу; переднее окно точно совпадает с задачей — удалить её с карточкой;
    /// иначе — `bindCurrentChat`.
    func toggleCurrentChat()
    /// Пункт меню «Добавить/Удалить текущее окно» (D16): окно отмены не учитывается (возврат — отдельный
    /// пункт), поэтому действие совпадает с подписью: точное совпадение — удалить с карточкой, иначе — добавить.
    func toggleCurrentWindow()
}

/// Набор сервисов BIND, который передаётся остальным частям приложения.
@MainActor
struct BindServices {
    let contextProvider: FrontmostContextProviding
    let capturer: BindingCapturing
    let activator: BindingActivating
    let permissions: PermissionsProviding
}

// MARK: - SWITCH

/// Переключение задач: по кругу (хоткеи) и напрямую (клик по задаче в списке).
@MainActor
protocol TaskSwitching: AnyObject {
    /// Определить текущую задачу по переднему окну, выбрать соседнюю по кругу,
    /// активировать её привязку, показать карточку и обновить время захода.
    func switchTask(_ direction: CycleDirection)
    /// Перейти к конкретной задаче.
    func activateTask(id: UUID)
}

/// ⌃⌥D «отметить сделанной / вернуть в работу»: задача переднего окна при точном совпадении,
/// иначе текущая; сохраняет tasks.json, показывает карточку, окна не переключает.
@MainActor
protocol DoneToggling: AnyObject {
    func toggleDone()
}

/// Карточка перехода: неактивирующая панель поверх всех рабочих столов.
@MainActor
protocol TransitionCardPresenting: AnyObject {
    func show(_ content: TransitionCardContent)
}

/// Глобальные хоткеи. `start` регистрирует их и вызывает `handler` на главном потоке.
@MainActor
protocol HotkeyRegistering: AnyObject {
    func start(handler: @escaping (HotkeyAction) -> Void)
    func stop()
}

// MARK: - Самопроверка

/// Результат одной самопроверки компонента для `Juggler --self-test`.
/// Самопроверка не запрашивает разрешений и не показывает окон.
struct SelfTestResult {
    let name: String
    let passed: Bool
    let detail: String

    init(_ name: String, passed: Bool, detail: String = "") {
        self.name = name
        self.passed = passed
        self.detail = detail
    }
}

/// Журнал приложения: `Logger(subsystem: JugglerLog.subsystem, category: "<область>")`.
enum JugglerLog {
    static let subsystem = "com.sefimov.juggler"
    static let app = Logger(subsystem: subsystem, category: "app")
}
