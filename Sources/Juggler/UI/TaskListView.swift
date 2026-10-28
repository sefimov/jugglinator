import AppKit
import JugglerCore
import SwiftUI

/// Menu bar panel: task list, editing, and actions below the list.
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
            // "away N min" is recomputed while the panel is open.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                taskList(now: context.date)
            }
            editorPanel
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 380)
        .background(WindowKeyObserver(onBecomeKey: refreshWindowContext, onResignKey: { state.resetWindowContext() }))
        .onAppear(perform: refreshWindowContext)
    }

    /// Read the window that was in front before the menu opened. Deferred to the next event loop
    /// pass so the panel has time to appear; does not request permissions.
    private func refreshWindowContext() {
        state.resetWindowContext()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                state.setWindowContext(UIActions.readWindowContext(environment: environment))
            }
        }
    }

    /// What the "Add/Remove current window" item does right now.
    private var windowAction: CurrentWindowMenuAction {
        CurrentWindowMenuAction.decide(context: state.windowContext, document: model.document)
    }

    // MARK: - Header and notices

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

    // MARK: - List

    @ViewBuilder
    private func taskList(now: Date) -> some View {
        let rows = TaskListPresenter.rows(for: model.document, now: now)
        if rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(loc("Задач пока нет."))
                Text(loc("Откройте чат и выберите «\(TaskToggleTexts.menuAddTitle)» ниже."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
        } else {
            List {
                ForEach(rows) { row in
                    TaskRowView(row: row, actions: actions(for: row, count: rows.count))
                        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                        .listRowSeparator(.hidden)
                }
                .onMove { offsets, destination in
                    model.update { TaskListOps.move(&$0, fromOffsets: offsets, toOffset: destination) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: CGFloat(TaskListPresenter.listHeight(rows: rows)))
        }
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

    // MARK: - Editing and removal

    @ViewBuilder
    private var editorPanel: some View {
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
        } else if state.pendingClearAll, !model.document.tasks.isEmpty {
            ClearConfirmationView(
                question: TaskListPresenter.clearAllConfirmation(count: model.document.tasks.count),
                onClear: {
                    model.clearAllTasks()
                    state.cancel()
                },
                onCancel: { state.cancel() })
        } else if state.pendingClearDone, doneCount > 0 {
            ClearConfirmationView(
                question: TaskListPresenter.clearDoneConfirmation(count: doneCount),
                onClear: {
                    model.clearDoneTasks()
                    state.cancel()
                },
                onCancel: { state.cancel() })
        } else if let id = state.pendingDeleteID, let task = model.document.task(withID: id) {
            DeleteConfirmationView(
                title: task.title,
                onDelete: {
                    model.removeTask(id, undoableByToggle: false)
                    state.cancel()
                },
                onCancel: { state.cancel() })
        }
    }

    // MARK: - Below the list

    private var doneCount: Int { model.document.tasks.filter(\.isDone).count }

    /// In a column: current window, restore removed, delete done, clear list, settings, quit (order — `MenuFooterItem.items`).
    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(MenuFooterItem.items(canRestore: model.lastRemoved != nil, hasTasks: !model.document.tasks.isEmpty,
                                         hasDone: doneCount > 0), id: \.self) { item in
                footerItem(item)
            }
        }
    }

    @ViewBuilder
    private func footerItem(_ item: MenuFooterItem) -> some View {
        switch item {
        case .currentWindow:
            let action = windowAction
            footerButton(action.title, systemImage: action.isRemove ? "minus.circle" : "plus.circle") {
                UIActions.toggleCurrentWindow(environment: environment, dismiss: { dismiss() })
            }
            .disabled(!state.windowContextLoaded)
            .help(loc("Чат или вкладка, которые были впереди до открытия меню: уже задача — удалить её, иначе — сделать задачей (⌃⌥⇥)"))
        case .restoreRemoved:
            footerButton(TaskToggleTexts.restoreMenuTitle, systemImage: "arrow.uturn.backward") {
                model.restoreLastRemoved()
            }
            .help(model.lastRemoved.map(TaskToggleTexts.restoreHelp) ?? "")
        case .clearDone:
            footerButton(TaskToggleTexts.clearDoneMenuTitle, systemImage: "checkmark.circle.badge.xmark") {
                state.askClearDone()
            }
        case .clearAll:
            footerButton(TaskToggleTexts.clearAllMenuTitle, systemImage: "trash") {
                state.askClearAll()
            }
        case .settings:
            footerButton(TaskToggleTexts.settingsMenuTitle, systemImage: "gearshape") {
                // Close the menu first, then open settings and bring them to front.
                let open = openSettings
                UIActions.afterClosingMenu({ dismiss() }) {
                    UIActions.activateForSettings()
                    open()
                }
            }
            .keyboardShortcut(",", modifiers: .command)
        case .quit:
            footerButton(TaskToggleTexts.quitMenuTitle, systemImage: "power") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private func footerButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 3)
    }
}

/// Reports when the menu bar panel window becomes key (menu opened) and stops being key.
/// Needed because `onAppear` of the `MenuBarExtra` panel does not fire on every opening.
private struct WindowKeyObserver: NSViewRepresentable {
    let onBecomeKey: () -> Void
    let onResignKey: () -> Void

    func makeNSView(context: Context) -> ObserverView { ObserverView() }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onBecomeKey = onBecomeKey
        view.onResignKey = onResignKey
    }

    final class ObserverView: NSView {
        var onBecomeKey: () -> Void = {}
        var onResignKey: () -> Void = {}
        private var tokens: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens = []
            guard let window else { return }
            let center = NotificationCenter.default
            tokens.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.onBecomeKey()
            })
            tokens.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.onResignKey()
            })
        }

        deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
    }
}
