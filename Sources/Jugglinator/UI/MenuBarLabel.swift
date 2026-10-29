import AppKit
import JugglerCore
import SwiftUI

/// Menu bar icon: a dot. Its color comes from the unfinished task left unvisited the longest
/// (excluding the current one); a gray outline if no tasks are in progress. The tooltip says which task
/// it is and how many minutes ago it was visited. If the frontmost window is a task, its number
/// is drawn inside the dot.
///
/// Redraws on any document change (switching, "done", adding, removing),
/// on language change, once a minute on a timer and when the frontmost window changes.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @StateObject private var frontWindow: FrontWindowTracker
    @StateObject private var ticker = MenuBarTicker()
    /// Tooltip in the selected language: a language change redraws the label.
    @ObservedObject private var language = LanguageController.shared

    init(model: AppModel, contextProvider: FrontmostContextProviding) {
        self.model = model
        _frontWindow = StateObject(wrappedValue: FrontWindowTracker(provider: contextProvider))
    }

    var body: some View {
        _ = ticker.tick
        _ = language.language
        let dot = MenuBarDotPresenter.dot(for: model.document, now: model.clock())
        let number = MenuBarDotPresenter.frontWindowNumber(context: frontWindow.context, document: model.document)
        StatusItemTooltip.apply(dot.tooltip)
        return Image(nsImage: MenuBarDotImage.image(for: dot.appearance, number: number))
            .help(dot.tooltip)
            .accessibilityLabel(dot.tooltip)
            // A switch or a hotkey changed the current task: the frontmost window is about to change too.
            .onChange(of: model.document.lastActiveTaskID) { frontWindow.refresh(after: 0.5) }
    }
}
