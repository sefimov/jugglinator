import Foundation
import JugglerCore

// Папка Sources/JugglerChecks/Bind/ принадлежит задаче BIND.
// Проверяйте здесь чистую логику из Sources/JugglerCore/Bind/.
// Можно добавлять файлы с `extension BindChecks` и вызывать их из `run`.

enum BindChecks: CheckSuite {
    static let name = "Bind"

    static func run(_ c: CheckRunner) {
    }
}
