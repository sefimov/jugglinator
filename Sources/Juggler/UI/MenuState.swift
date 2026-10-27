import Foundation
import JugglerCore

/// Состояние панели меню-бара, которое не сохраняется: что сейчас правится и что удаляется.
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
    @Published var newTitle = ""

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
