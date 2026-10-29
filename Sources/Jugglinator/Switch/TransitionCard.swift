import AppKit
import Foundation
import JugglerCore
import SwiftUI

/// Transition card panel: does not activate the app and never becomes key,
/// is visible on all Spaces and over full-screen apps, clicks pass through.
final class TransitionCardPanel: NSPanel {
    static let cardLevel = NSWindow.Level.popUpMenu
    static let behavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
    ]

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        isFloatingPanel = true
        level = Self.cardLevel
        collectionBehavior = Self.behavior
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        worksWhenModal = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        alphaValue = 0
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Flags required by acceptance; checked in the self-test.
    var flagProblems: [String] {
        var problems: [String] = []
        if !styleMask.contains(.nonactivatingPanel) { problems.append("нет .nonactivatingPanel") }
        if canBecomeKey || canBecomeMain { problems.append("может стать ключевой") }
        if !ignoresMouseEvents { problems.append("не пропускает клики") }
        if !collectionBehavior.contains(.canJoinAllSpaces) { problems.append("не на всех рабочих столах") }
        if !collectionBehavior.contains(.fullScreenAuxiliary) { problems.append("не поверх full-screen") }
        if level < .statusBar { problems.append("низкий уровень окна") }
        if hidesOnDeactivate { problems.append("прячется при деактивации") }
        return problems
    }
}

/// What the card shows.
enum CardDisplay: Equatable {
    case task(TransitionCardContent)
    /// A service message, e.g. "no tasks in progress".
    case message(String)
}

/// A card that can also show a service message.
@MainActor
protocol TransitionMessagePresenting: AnyObject {
    func showMessage(_ text: String)
    /// A message visible for about `duration` seconds (including fade-in and fade-out),
    /// e.g. the removal card for the whole ⌃⌥⇥ undo window.
    func showMessage(_ text: String, duration: TimeInterval)
}

/// Card display: fade-in, ~1 s visible, smooth fade-out (≈1.4 s total).
@MainActor
final class PanelCardPresenter: TransitionCardPresenting, TransitionMessagePresenting {
    let timing: CardTiming
    private var panelStorage: TransitionCardPanel?
    private var hosting: NSHostingView<TransitionCardView>?
    private var generation = 0

    init(timing: CardTiming = .standard) {
        self.timing = timing
    }

    /// The panel is created on first display (or in the self-test).
    var panel: TransitionCardPanel {
        if let panelStorage { return panelStorage }
        let panel = TransitionCardPanel()
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .vibrantDark)
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        let hosting = NSHostingView(rootView: TransitionCardView(display: .message("")))
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)
        panel.contentView = effect
        self.hosting = hosting
        self.panelStorage = panel
        return panel
    }

    func show(_ content: TransitionCardContent) {
        present(.task(content))
    }

    func showMessage(_ text: String) {
        present(.message(text))
    }

    func showMessage(_ text: String, duration: TimeInterval) {
        present(.message(text), hold: max(duration - timing.fadeIn - timing.fadeOut, timing.hold))
    }

    /// Lay out the card without showing it. Returns its size (for the self-test).
    @discardableResult
    func layout(_ display: CardDisplay) -> NSSize {
        let panel = self.panel
        guard let hosting else { return .zero }
        hosting.rootView = TransitionCardView(display: display)
        let size = hosting.fittingSize
        panel.setContentSize(size)
        hosting.frame = NSRect(origin: .zero, size: size)
        return size
    }

    private func present(_ display: CardDisplay, hold: TimeInterval? = nil) {
        generation += 1
        let current = generation
        let size = layout(display)
        let panel = self.panel
        panel.setFrameOrigin(origin(for: size))
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = timing.fadeIn
            panel.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timing.fadeIn + (hold ?? timing.hold)) { [weak self] in
            MainActor.assumeIsolated { self?.fadeOut(generation: current) }
        }
    }

    private func fadeOut(generation expected: Int) {
        guard expected == generation, let panel = panelStorage else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = timing.fadeOut
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A new card may have arrived during the fade-out — don't hide it.
                guard let self, expected == self.generation else { return }
                self.panelStorage?.orderOut(nil)
            }
        })
    }

    /// The screen under the cursor; the card is centered, slightly above the middle.
    private func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(
            x: (frame.midX - size.width / 2).rounded(),
            y: (frame.minY + frame.height * 0.62 - size.height / 2).rounded())
    }
}

/// The card view.
struct TransitionCardView: View {
    let display: CardDisplay

    var body: some View {
        Group {
            switch display {
            case .task(let content): taskBody(content)
            case .message(let text):
                Text(text)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(width: 380, alignment: .leading)
        .environment(\.colorScheme, .dark)
    }

    private func taskBody(_ content: TransitionCardContent) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(content.number)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .frame(width: 44, height: 44)
                .background(Circle().fill(StalenessPalette.color(content.staleness).opacity(0.85)))
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let source = content.source {
                        Image(systemName: source.symbolName).foregroundStyle(.white.opacity(0.7))
                    }
                    Text(content.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !content.note.isEmpty {
                    Text(content.note)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(content.absenceText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(StalenessPalette.color(content.staleness))
                if let hint = content.hint {
                    Label(hint, systemImage: content.source == nil ? "link.badge.plus" : "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private enum StalenessPalette {
    static func color(_ level: StalenessLevel) -> Color {
        switch level {
        case .never: return .gray
        case .fresh: return .green
        case .aging: return .yellow
        case .stale: return .orange
        case .forgotten: return .red
        }
    }
}
