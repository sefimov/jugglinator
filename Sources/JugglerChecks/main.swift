import Foundation
import JugglerCore

// `swift run JugglerChecks [-v] [Область…]`
//   -v        — печатать каждую прошедшую проверку;
//   Область   — запустить только наборы с этими именами (Core, UI, Switch, Bind);
//   --self-fail — добавить заведомо проваленную проверку (убедиться, что код выхода ненулевой).
// Код выхода 0 — всё прошло, 1 — есть провалы.
//
// Наборы областей уже перечислены ниже; каждая задача наполняет свой файл
// Sources/JugglerChecks/<Область>/<Область>Checks.swift и этот файл не трогает.

let suites: [CheckSuite.Type] = [
    CoreChecks.self,
    UIChecks.self,
    SwitchChecks.self,
    BindChecks.self,
]

let arguments = Array(CommandLine.arguments.dropFirst())
let verbose = arguments.contains("-v")
let filter = Set(arguments.filter { !$0.hasPrefix("-") }.map { $0.lowercased() })

// Тексты в проверках — русские (язык ключей), независимо от языка системы и CI.
Localizer.shared.setLanguage(Localizer.keyLanguage)

let runner = CheckRunner(verbose: verbose)
for suite in suites where filter.isEmpty || filter.contains(suite.name.lowercased()) {
    runner.runSuite(suite)
}
if arguments.contains("--self-fail") {
    runner.group("--self-fail") { runner.expect(false, "заведомо проваленная проверка") }
}
exit(runner.finish())
