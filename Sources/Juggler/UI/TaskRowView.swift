import JugglerCore
import SwiftUI

/// Действия над строкой списка.
struct TaskRowActions {
    var canMoveUp: Bool
    var canMoveDown: Bool
    var open: () -> Void
    var toggleDone: () -> Void
    var rename: () -> Void
    var editNote: () -> Void
    var moveUp: () -> Void
    var moveDown: () -> Void
    var unbind: () -> Void
    var delete: () -> Void
}

/// Строка задачи: отметка текущей, номер, значок источника, название и заметка,
/// «не был N мин» с цветом старения, «сделано» и меню действий.
struct TaskRowView: View {
    let row: TaskRow
    let actions: TaskRowActions

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "play.fill")
                .font(.system(size: 7))
                .foregroundStyle(Color.accentColor)
                .opacity(row.isCurrent ? 1 : 0)
                .frame(width: 8)
                .accessibilityLabel(row.isCurrent ? loc("Текущая задача") : "")

            Text("\(row.number)")
                .font(.body.monospacedDigit().weight(row.isCurrent ? .bold : .regular))
                .frame(minWidth: 16, alignment: .trailing)

            Image(systemName: row.source?.symbolName ?? "circle.dashed")
                .foregroundStyle(row.source == nil ? .tertiary : .secondary)
                .frame(width: 18)
                .help(row.bindingHelp)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .fontWeight(row.isCurrent ? .semibold : .regular)
                    .strikethrough(row.isDone)
                    .foregroundStyle(row.isDone ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !row.note.isEmpty {
                    Text(row.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .help(row.note.isEmpty ? row.title : "\(row.title)\n\(row.note)")

            Spacer(minLength: 4)

            Text(row.isDone ? loc("сделано") : row.absenceText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(row.isDone ? Color.secondary : row.staleness.color)
                .lineLimit(1)

            Button(action: actions.toggleDone) {
                Image(systemName: row.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(row.isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(row.isDone ? loc("Вернуть в работу") : loc("Отметить «сделано»"))

            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(loc("Действия с задачей"))
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: actions.open)
        .contextMenu { menuItems }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button(loc("Открыть"), action: actions.open)
        Divider()
        Button(loc("Переименовать…"), action: actions.rename)
        Button(row.note.isEmpty ? loc("Добавить заметку…") : loc("Изменить заметку…"), action: actions.editNote)
        Button(row.isDone ? loc("Вернуть в работу") : loc("Отметить «сделано»"), action: actions.toggleDone)
        Divider()
        Button(loc("Переместить выше"), action: actions.moveUp).disabled(!actions.canMoveUp)
        Button(loc("Переместить ниже"), action: actions.moveDown).disabled(!actions.canMoveDown)
        if row.source != nil {
            Divider()
            Button(loc("Снять привязку"), action: actions.unbind)
        }
        Divider()
        Button(loc("Удалить…"), role: .destructive, action: actions.delete)
    }
}
