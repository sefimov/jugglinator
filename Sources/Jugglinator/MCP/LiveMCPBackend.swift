import Foundation
import JugglerCore

/// The MCP tools over the live app: `AppModel` for the list, BIND for the frontmost window,
/// the SWITCH switcher for activation and the card for feedback. Called on the main thread only
/// (`MCPSocketServer` dispatches every request there), hence `MainActor.assumeIsolated`.
final class LiveMCPBackend: MCPTaskBackend {
    private let model: AppModel
    private let bind: BindServices
    private let switcher: TaskSwitching
    private let card: TransitionCardPresenting

    @MainActor
    init(model: AppModel, bind: BindServices, switcher: TaskSwitching, card: TransitionCardPresenting) {
        self.model = model
        self.bind = bind
        self.switcher = switcher
        self.card = card
    }

    func snapshot() -> MCPSnapshot {
        MainActor.assumeIsolated {
            // "Current" as the hotkey cycle sees it: the frontmost window's task, otherwise the last active one.
            let context = bind.contextProvider.currentContext()
            let document = model.document
            return MCPSnapshot(document: document, now: model.clock(),
                               currentTaskID: SwitchPlanner.currentTaskID(context: context, document: document))
        }
    }

    func switchToTask(id: UUID) -> MCPActionOutcome {
        MainActor.assumeIsolated {
            guard model.document.task(withID: id) != nil else { return .failed("Task not found.") }
            mcpLog.info("MCP: switch to task \(self.model.document.number(of: id) ?? 0)")
            if let cycle = switcher as? CycleTaskSwitcher {
                switch cycle.activate(id: id) {
                case .failed(let message)?: return .done(warning: message)
                case .fallback(let message)?: return .done(warning: message)
                case .activated?, nil: return .done(warning: nil)
                }
            }
            switcher.activateTask(id: id)
            return .done(warning: nil)
        }
    }

    func addCurrentWindow() -> MCPAddOutcome {
        MainActor.assumeIsolated {
            let context = bind.contextProvider.currentContext()
            let plan = SwitchPlanner.frontWindow(context: context, document: model.document, capture: bind.capturer.captureBinding)
            mcpLog.info("MCP: add current window → \(String(describing: plan), privacy: .public)")
            switch plan {
            case .task(let id):
                return .alreadyTask(id)
            case .add(let binding, let title):
                guard let id = FrontWindowAdder.add(binding, title: title, model: model, card: card) else {
                    return .failed("The task could not be created.")
                }
                return .added(id)
            case .needsLink:
                return .failed("This window needs a pasted link to be bound (a Claude chat whose id could not be read, "
                    + "or a ChatGPT thread Jugglinator could not identify). Ask the user to press the add hotkey (Control-Option-Tab "
                    + "by default) in that window and paste the link.")
            case .unavailable(let message):
                return .failed(message ?? "There is no window to add: the desktop, Jugglinator itself, or a window without a title is in front.")
            }
        }
    }

    func setDone(id: UUID, _ done: Bool) -> Bool {
        MainActor.assumeIsolated {
            guard model.document.task(withID: id) != nil else { return false }
            model.update { TaskListOps.setDone(&$0, id: id, done) }
            if let number = model.document.number(of: id), let task = model.document.task(withID: id) {
                (card as? TransitionMessagePresenting)?.showMessage(DoneToggleTexts.card(number: number, title: task.title, isDone: done))
            }
            return true
        }
    }

    func setNote(id: UUID, _ note: String) -> Bool {
        MainActor.assumeIsolated {
            guard model.document.task(withID: id) != nil else { return false }
            model.update { TaskListOps.setNote(&$0, id: id, to: note) }
            return true
        }
    }
}
