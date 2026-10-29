import AppKit
import Foundation
import JugglerCore
import os

let uiLog = Logger(subsystem: JugglerLog.subsystem, category: "ui")

/// Menu actions that move focus to another app.
@MainActor
enum UIActions {
    /// Pause after closing the menu bar panel: lets the window the user was in come to front.
    static let handOffDelay: TimeInterval = 0.3

    /// Close the menu bar panel, return focus to the previous app and perform the action.
    static func afterClosingMenu(_ dismiss: () -> Void, _ action: @escaping @MainActor () -> Void) {
        dismiss()
        NSApp.deactivate()
        DispatchQueue.main.asyncAfter(deadline: .now() + handOffDelay) {
            MainActor.assumeIsolated { action() }
        }
    }

    /// Go to a task via the switcher (SWITCH): binding activation, card, visit time.
    static func open(taskID: UUID, environment: AppEnvironment, dismiss: () -> Void) {
        afterClosingMenu(dismiss) {
            environment.switcher.activateTask(id: taskID)
        }
    }

    /// Context of the window that was in front before the menu opened (if Jugglinator itself is in front — of the last
    /// active other app). Shows no system prompts: without permissions returns whatever it could get.
    static func readWindowContext(environment: AppEnvironment) -> FrontmostContext {
        environment.bind.contextProvider.currentContext()
    }

    /// "Add/Remove current window" (D16): if the window is already a task, remove it (card and undo, like ⌃⌥⇥),
    /// otherwise make the current chat a task. The undo window is ignored: restore is a separate item.
    static func toggleCurrentWindow(environment: AppEnvironment, dismiss: () -> Void) {
        afterClosingMenu(dismiss) {
            environment.binder.toggleCurrentWindow()
        }
    }

    /// Open the settings window and bring it to front (the app has no Dock icon).
    static func activateForSettings() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
