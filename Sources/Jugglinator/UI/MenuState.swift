import Foundation
import JugglerCore

/// Non-persisted menu bar panel state: what is being edited and what is being removed,
/// and the window that was in front before the menu opened.
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
    /// The "Delete all N tasks?" prompt is shown.
    @Published var pendingClearAll = false
    /// The "Delete N done tasks?" prompt is shown.
    @Published var pendingClearDone = false
    /// Context of the window that was in front before the menu opened; `nil` — not read yet (panel just opened).
    @Published var windowContext: FrontmostContext?
    /// Context has been read for the current panel opening (even if nothing could be read).
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
        pendingClearAll = false
        pendingClearDone = false
        editing = Editing(taskID: id, field: field)
    }

    func askDelete(_ id: UUID) {
        editing = nil
        pendingClearAll = false
        pendingClearDone = false
        pendingDeleteID = id
    }

    func askClearAll() {
        editing = nil
        pendingDeleteID = nil
        pendingClearDone = false
        pendingClearAll = true
    }

    func askClearDone() {
        editing = nil
        pendingDeleteID = nil
        pendingClearAll = false
        pendingClearDone = true
    }

    func cancel() {
        editing = nil
        pendingDeleteID = nil
        pendingClearAll = false
        pendingClearDone = false
    }
}
