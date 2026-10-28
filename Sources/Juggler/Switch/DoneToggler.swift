import AppKit
import Foundation
import JugglerCore

/// ⌃§ "mark done / back to in progress" (D24). Picking the task and toggling live in JugglerCore
/// (`DoneToggle`); here: front window context, saving to tasks.json, the card and the sound.
/// Windows are not switched.
@MainActor
final class LiveDoneToggler: DoneToggling {
    private let model: AppModel
    private let bind: BindServices
    private let card: TransitionCardPresenting
    private let beep: () -> Void

    init(model: AppModel, bind: BindServices, card: TransitionCardPresenting, beep: @escaping () -> Void = { NSSound.beep() }) {
        self.model = model
        self.bind = bind
        self.card = card
        self.beep = beep
    }

    func toggleDone() {
        var result = DoneToggleResult.noTasks
        model.update { document in
            result = DoneToggle.toggle(&document) { bind.contextProvider.currentContext() }
        }
        if !result.didChange { beep() }
        switchLog.info("⌃§: \(String(describing: result), privacy: .public)")
        (card as? TransitionMessagePresenting)?.showMessage(DoneToggleTexts.message(for: result))
    }
}
