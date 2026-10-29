import AppKit

/// Tooltip for the menu bar icon.
///
/// SwiftUI `.help` on the `MenuBarExtra` label does not reach the status item button, so we set the
/// tooltip ourselves: find the status item button (`NSStatusBarButton`) in the app's windows and
/// set its `toolTip`. The call is idempotent; if the button isn't there yet, retry after short pauses.
@MainActor
enum StatusItemTooltip {
    static func apply(_ text: String, retries: [TimeInterval] = [0.3, 1.5, 5]) {
        if !set(text), let next = retries.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + next) {
                apply(text, retries: Array(retries.dropFirst()))
            }
        }
    }

    /// `true` if the tooltip was set on at least one status item button.
    @discardableResult
    static func set(_ text: String) -> Bool {
        var found = false
        for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBar") {
            if let content = window.contentView {
                for button in statusButtons(in: content) {
                    if button.toolTip != text { button.toolTip = text }
                    found = true
                }
            }
        }
        return found
    }

    private static func statusButtons(in view: NSView) -> [NSButton] {
        var result: [NSButton] = []
        if let button = view as? NSButton { result.append(button) }
        for sub in view.subviews { result += statusButtons(in: sub) }
        return result
    }

    /// The button's current tooltip (for checks).
    static var currentToolTip: String? {
        for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBar") {
            if let content = window.contentView, let button = statusButtons(in: content).first { return button.toolTip }
        }
        return nil
    }
}
