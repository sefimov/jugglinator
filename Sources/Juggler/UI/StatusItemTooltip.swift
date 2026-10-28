import AppKit

/// Подсказка у иконки в меню-баре.
///
/// SwiftUI `.help` на метке `MenuBarExtra` не доходит до кнопки статус-элемента, поэтому подсказку
/// выставляем сами: находим кнопку статус-элемента (`NSStatusBarButton`) в окнах приложения и
/// задаём ей `toolTip`. Вызов идемпотентный; если кнопки ещё нет, повторяем через короткие паузы.
@MainActor
enum StatusItemTooltip {
    static func apply(_ text: String, retries: [TimeInterval] = [0.3, 1.5, 5]) {
        if !set(text), let next = retries.first {
            DispatchQueue.main.asyncAfter(deadline: .now() + next) {
                apply(text, retries: Array(retries.dropFirst()))
            }
        }
    }

    /// `true`, если хотя бы одной кнопке статус-элемента подсказка выставлена.
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

    /// Текущая подсказка кнопки (для проверки).
    static var currentToolTip: String? {
        for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBar") {
            if let content = window.contentView, let button = statusButtons(in: content).first { return button.toolTip }
        }
        return nil
    }
}
