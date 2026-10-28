import JugglerCore
import SwiftUI

/// Правка названия и заметки «зачем / дальше» прямо в панели меню-бара.
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
            Text("Задача \(number)").font(.subheadline.weight(.semibold))
            TextField("Название", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .title)
                .onSubmit(save)
            Text("Заметка — зачем / что дальше")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $note)
                .font(.body)
                .frame(height: 64)
                .focused($focus, equals: .note)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.35)))
            HStack {
                if TaskListOps.cleanTitle(title).isEmpty {
                    Text("Пустое название не сохранится")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Отмена", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Сохранить", action: save)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Сохранить (⌘↩)")
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

/// Подтверждение удаления задачи.
struct DeleteConfirmationView: View {
    let title: String
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TaskListPresenter.deleteConfirmation(title: title))
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Задача, заметка и привязка будут удалены. Это нельзя отменить.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Отмена", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Удалить", role: .destructive, action: onDelete)
                    .tint(.red)
            }
        }
    }
}

/// Подтверждение очистки всего списка.
struct ClearAllConfirmationView: View {
    let count: Int
    let onClear: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TaskListPresenter.clearAllConfirmation(count: count))
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(TaskListPresenter.clearAllWarning)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Отмена", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Удалить", role: .destructive, action: onClear)
                    .tint(.red)
            }
        }
    }
}
