import AppKit
import Foundation

/// Раз в минуту (и после пробуждения Мака) просит иконку меню-бара пересчитать цвет:
/// время идёт, даже когда документ не меняется.
@MainActor
final class MenuBarTicker: ObservableObject {
    @Published private(set) var tick = 0
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(interval: TimeInterval = 60) {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fire() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.fire() }
        }
    }

    deinit {
        timer?.invalidate()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    private func fire() { tick &+= 1 }
}
