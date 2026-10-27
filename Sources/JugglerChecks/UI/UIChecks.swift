import Foundation
import JugglerCore

// Папка Sources/JugglerChecks/UI/ принадлежит задаче UI.
// Проверяйте здесь чистую логику из Sources/JugglerCore/UI/.
// Можно добавлять файлы с `extension UIChecks` и вызывать их из `run`.

enum UIChecks: CheckSuite {
    static let name = "UI"

    static func run(_ c: CheckRunner) {
    }
}
