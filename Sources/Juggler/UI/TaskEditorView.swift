import JugglerCore
import SwiftUI

/// Editing the title and the "why / next" note right in the menu bar panel.
struct TaskEditorView: View {
    let number: Int
    let initialField: MenuState.EditorField
    let onSave: (_ title: String, _ note: String) -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var note: String
    @FocusState private var focus: MenuState.EditorField?

    init(
        number: Int, title: String, note: String, field: MenuState.EditorField,
        onSave: @escaping (_ title: String, _ note: String) -> Void, onCancel: @escaping () -> Void
    ) {
        self.number = number
        self.initialField = field
        self.onSave = onSave
        self.onCancel = onCancel
        _title = State(initialValue: title)
        _note = State(initialValue: note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc("Задача \(number)")).font(.subheadline.weight(.semibold))
            TextField(loc("Название"), text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .title)
                .onSubmit(save)
            Text(loc("Заметка — зачем / что дальше"))
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $note)
                .font(.body)
                .frame(height: 64)
                .focused($focus, equals: .note)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.35)))
            HStack {
                if TaskListOps.cleanTitle(title).isEmpty {
                    Text(loc("Пустое название не сохранится"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(loc("Отмена"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(loc("Сохранить"), action: save)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help(loc("Сохранить (⌘↩)"))
            }
        }
        .onAppear {
            DispatchQueue.main.async { focus = initialField }
        }
    }

    private func save() {
        onSave(title, note)
    }
}

/// Task deletion confirmation.
struct DeleteConfirmationView: View {
    let title: String
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TaskListPresenter.deleteConfirmation(title: title))
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(loc("Задача, заметка и привязка будут удалены. Это нельзя отменить."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(loc("Отмена"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(loc("Удалить"), role: .destructive, action: onDelete)
                    .tint(.red)
            }
        }
    }
}

/// Confirmation for clearing the whole list or deleting the done tasks: `question` is the prompt.
struct ClearConfirmationView: View {
    let question: String
    let onClear: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(question)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(TaskListPresenter.clearAllWarning)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(loc("Отмена"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(loc("Удалить"), role: .destructive, action: onClear)
                    .tint(.red)
            }
        }
    }
}
