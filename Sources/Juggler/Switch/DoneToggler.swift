import AppKit
import Foundation
import JugglerCore

/// ⌃§ "mark done / back to in progress" (D24) acts only on the frontmost window (`SwitchPlanner.frontWindow`):
/// - the window is a task — its mark is toggled (`DoneToggle`), saved to tasks.json, with a card;
/// - the window is not in the list — it is added as a new task, the mark is not touched;
///   a Claude or ChatGPT window that needs a link goes through the usual binding flow with dialogs;
/// - the window cannot be added (desktop, Juggler itself) — a sound and a card with an explanation.
/// The last active task is never toggled instead. Windows are not switched.
@MainActor
final class LiveDoneToggler: DoneToggling {
    private let model: AppModel
    private let bind: BindServices
    private let card: TransitionCardPresenting
    /// Adding the frontmost window with dialogs (link prompt): "make the current chat a task".
    private let addWithDialogs: () -> Void
    private let beep: () -> Void

    init(model: AppModel, bind: BindServices, card: TransitionCardPresenting,
         addWithDialogs: @escaping () -> Void, beep: @escaping () -> Void = { NSSound.beep() }) {
        self.model = model
        self.bind = bind
        self.card = card
        self.addWithDialogs = addWithDialogs
        self.beep = beep
    }

    func toggleDone() {
        let context = bind.contextProvider.currentContext()
        let plan = SwitchPlanner.frontWindow(context: context, document: model.document, capture: bind.capturer.captureBinding)
        switchLog.info("⌃§: \(String(describing: plan), privacy: .public)")
        let messages = card as? TransitionMessagePresenting
        switch plan {
        case .task(let id):
            var result: DoneToggleResult?
            model.update { result = DoneToggle.toggle(&$0, id: id) }
            if let result { messages?.showMessage(DoneToggleTexts.message(for: result)) }
        case .add(let binding, let title):
            FrontWindowAdder.add(binding, title: title, model: model, card: card)
        case .needsLink:
            addWithDialogs()
        case .unavailable(let message):
            beep()
            messages?.showMessage(message ?? DoneToggleTexts.noCurrentTaskMessage)
        }
    }
}
