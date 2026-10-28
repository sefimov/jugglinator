import AppKit
import JugglerCore
import SwiftUI

/// Иконка в меню-баре: кружок. Цвет — по несделанной задаче, к которой не возвращались дольше
/// всего (кроме текущей); серый контур, если задач в работе нет. Подсказка — какая это задача
/// и сколько минут назад в неё заходили.
///
/// Перерисовывается при любом изменении документа (переключение, «сделано», добавление, удаление),
/// при смене языка и раз в минуту по таймеру.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @StateObject private var ticker = MenuBarTicker()
    /// Подсказка на выбранном языке: смена языка перерисовывает метку.
    @ObservedObject private var language = LanguageController.shared

    var body: some View {
        _ = ticker.tick
        _ = language.language
        let dot = MenuBarDotPresenter.dot(for: model.document, now: model.clock())
        StatusItemTooltip.apply(dot.tooltip)
        return Image(nsImage: MenuBarDotImage.image(for: dot.appearance))
            .help(dot.tooltip)
            .accessibilityLabel(dot.tooltip)
    }
}
