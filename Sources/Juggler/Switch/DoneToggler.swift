import AppKit
import Foundation
import JugglerCore

/// ⌃⌥D «отметить сделанной / вернуть в работу» (D24). Выбор задачи и переключение — в JugglerCore
/// (`DoneToggle`); здесь контекст переднего окна, сохранение в tasks.json, карточка и звук.
/// Окна не переключаются.
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
        switchLog.info("⌃⌥D: \(String(describing: result), privacy: .public)")
        (card as? TransitionMessagePresenting)?.showMessage(DoneToggleTexts.message(for: result))
    }
}
