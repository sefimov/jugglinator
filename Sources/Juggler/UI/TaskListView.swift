import AppKit
import JugglerCore
import SwiftUI

/// Панель меню-бара: список задач, правка, добавление и действия.
struct TaskListView: View {
    let environment: AppEnvironment
    @ObservedObject var model: AppModel
    @StateObject private var state = MenuState()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            notices
            // «не был N мин» пересчитывается, пока панель открыта.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                taskList(now: context.date)
            }
            bottomPanel
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 380)
    }

    // MARK: - Заголовок и уведомления

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Juggler").font(.headline)
            Text(TaskListPresenter.summary(for: model.document))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private var notices: some View {
        if let notice = TaskListPresenter.loadNotice(model.loadOutcome) {
            Label(notice, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let error = model.lastSaveError {
            Label(error, systemImage: "exclamationmark.octagon")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Список

    @ViewBuilder
    private func taskList(now: Date) -> some View {
        let rows = TaskListPresenter.rows(for: model.document, now: now)
        if rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Задач пока нет.")
                Text("Откройте чат и выберите «\(TaskToggleTexts.actionTitle)» или добавьте задачу ниже.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
        } else {
            List {
                ForEach(rows) { row in
                    TaskRowView(row: row, actions: actions(for: row, count: rows.count))
                }
                .onMove { offsets, destination in
                    model.update { TaskListOps.move(&$0, fromOffsets: offsets, toOffset: destination) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: listHeight(rows: rows))
        }
    }

    private func listHeight(rows: [TaskRow]) -> CGFloat {
        let height = rows.reduce(CGFloat(6)) { sum, row in sum + (row.note.isEmpty ? 34 : 48) }
        return min(height, 360)
    }

    private func actions(for row: TaskRow, count: Int) -> TaskRowActions {
        let id = row.id
        return TaskRowActions(
            canMoveUp: row.number > 1,
            canMoveDown: row.number < count,
            open: { UIActions.open(taskID: id, environment: environment, dismiss: { dismiss() }) },
            toggleDone: { model.update { TaskListOps.toggleDone(&$0, id: id) } },
            rename: { state.edit(id, field: .title) },
            editNote: { state.edit(id, field: .note) },
            moveUp: { model.update { TaskListOps.move(&$0, id: id, by: -1) } },
            moveDown: { model.update { TaskListOps.move(&$0, id: id, by: 1) } },
            unbind: { model.update { TaskListOps.clearBinding(&$0, id: id) } },
            delete: { state.askDelete(id) })
    }

    // MARK: - Правка, удаление, добавление

    @ViewBuilder
    private var bottomPanel: some View {
        if let editing = state.editing, let task = model.document.task(withID: editing.taskID),
           let number = model.document.number(of: task.id) {
            TaskEditorView(
                number: number, title: task.title, note: task.note, field: editing.field,
                onSave: { title, note in
                    model.update {
                        TaskListOps.rename(&$0, id: task.id, to: title)
                        TaskListOps.setNote(&$0, id: task.id, to: note)
                    }
                    state.cancel()
                },
                onCancel: { state.cancel() })
            .id(editing.taskID)
        } else if let id = state.pendingDeleteID, let task = model.document.task(withID: id) {
            DeleteConfirmationView(
                title: task.title,
                onDelete: {
                    model.removeTask(id, undoableByToggle: false)
                    state.cancel()
                },
                onCancel: { state.cancel() })
        } else {
            addField
        }
    }

    private var addField: some View {
        HStack(spacing: 6) {
            TextField("Новая задача", text: $state.newTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addTask)
            Button(action: addTask) {
                Image(systemName: "plus")
            }
            .help("Добавить задачу без привязки")
        }
    }

    private func addTask() {
        let title = state.newTitle
        let now = model.clock()
        model.update { TaskListOps.add(&$0, title: title, now: now) }
        state.newTitle = ""
    }

    // MARK: - Нижние кнопки

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                UIActions.toggleCurrentTask(environment: environment, dismiss: { dismiss() })
            } label: {
                Label(TaskToggleTexts.actionTitle, systemImage: "link.badge.plus")
            }
            .buttonStyle(.borderless)
            .help("Чат или вкладка, которые были впереди до открытия меню: уже задача — удалить её, иначе — сделать задачей (⌃⌥ + клавиша над Tab)")

            if let removed = model.lastRemoved {
                Button {
                    model.restoreLastRemoved()
                } label: {
                    Label(TaskToggleTexts.restoreMenuTitle, systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help(TaskToggleTexts.restoreHelp(removed))
            }

            HStack {
                Button("Настройки…") {
                    UIActions.activateForSettings()
                    openSettings()
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(",", modifiers: .command)
                Spacer()
                Button("Выйти из Juggler") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}
