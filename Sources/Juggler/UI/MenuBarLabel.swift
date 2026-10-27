import AppKit
import JugglerCore
import SwiftUI

/// Иконка в меню-баре: номер текущей задачи.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let number = model.currentTaskNumber
        if let symbol = TaskListPresenter.menuBarSymbol(currentNumber: number),
           NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil {
            Image(systemName: symbol)
                .accessibilityLabel(TaskListPresenter.menuBarHelp(document: model.document))
        } else if number == nil {
            Image(systemName: TaskListPresenter.menuBarEmptySymbol)
                .accessibilityLabel(TaskListPresenter.menuBarHelp(document: model.document))
        } else {
            Text(TaskListPresenter.menuBarText(currentNumber: number))
                .monospacedDigit()
                .accessibilityLabel(TaskListPresenter.menuBarHelp(document: model.document))
        }
    }
}
