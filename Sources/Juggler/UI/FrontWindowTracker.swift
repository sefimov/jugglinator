import AppKit
import Foundation
import JugglerCore

/// Keeps the frontmost window context for the menu bar icon: whether that window is a task
/// is decided by the label against the current document (`MenuBarDotPresenter.frontWindowNumber`),
/// so adding, removing or reordering tasks shows up at once.
///
/// The context is re-read when another app becomes active (after a short pause: its window
/// gets focus a bit later) and every few seconds: switching tabs or windows inside one app
/// sends no notification. Publishes only when the context actually changed.
@MainActor
final class FrontWindowTracker: ObservableObject {
    @Published private(set) var context: FrontmostContext?
    private let provider: FrontmostContextProviding
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?

    init(provider: FrontmostContextProviding, interval: TimeInterval = 3) {
        self.provider = provider
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh(after: 0.3) }
        }
        refresh()
    }

    deinit {
        timer?.invalidate()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }

    /// Re-read the context now or after `delay` seconds (e.g. after a switch: the window is still coming up).
    func refresh(after delay: TimeInterval = 0) {
        guard delay > 0 else {
            let current = provider.currentContext()
            if current != context { context = current }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }
}
