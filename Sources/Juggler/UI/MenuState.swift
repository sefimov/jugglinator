import Foundation
import JugglerCore

/// Состояние панели меню-бара, которое не сохраняется: что сейчас правится и что удаляется,
/// и окно, которое было впереди до открытия меню.
@MainActor
final class MenuState: ObservableObject {
    enum EditorField: Hashable {
        case title
        case note
    }

    struct Editing: Equatable {
        var taskID: UUID
        var field: EditorField
    }

    @Published var editing: Editing?
    @Published var pendingDeleteID: UUID?
    /// Контекст окна, бывшего впереди до открытия меню; `nil` — ещё не прочитан (панель только открылась).
    @Published var windowContext: FrontmostContext?
    /// Контекст прочитан для текущего открытия панели (даже если прочитать ничего не удалось).
    @Published var windowContextLoaded = false

    func resetWindowContext() {
        windowContext = nil
        windowContextLoaded = false
    }

    func setWindowContext(_ context: FrontmostContext) {
        windowContext = context
        windowContextLoaded = true
    }

    func edit(_ id: UUID, field: EditorField) {
        pendingDeleteID = nil
        editing = Editing(taskID: id, field: field)
    }

    func askDelete(_ id: UUID) {
        editing = nil
        pendingDeleteID = id
    }

    func cancel() {
        editing = nil
        pendingDeleteID = nil
    }
}
