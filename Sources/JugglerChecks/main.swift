import Foundation
import JugglerCore

// `swift run JugglerChecks [-v] [Area…]`
//   -v        — print every passing check;
//   Area      — run only the suites with these names (Core, UI, Switch, Bind);
//   --self-fail — add a deliberately failing check (to verify the exit code is non-zero).
// Exit code 0 — everything passed, 1 — there are failures.
//
// The area suites are already listed below; each task fills its own file
// Sources/JugglerChecks/<Area>/<Area>Checks.swift and does not touch this file.

let suites: [CheckSuite.Type] = [
    CoreChecks.self,
    UIChecks.self,
    SwitchChecks.self,
    BindChecks.self,
]

let arguments = Array(CommandLine.arguments.dropFirst())
let verbose = arguments.contains("-v")
let filter = Set(arguments.filter { !$0.hasPrefix("-") }.map { $0.lowercased() })

// Texts in the checks are Russian (the key language), regardless of the system and CI language.
Localizer.shared.setLanguage(Localizer.keyLanguage)

let runner = CheckRunner(verbose: verbose)
for suite in suites where filter.isEmpty || filter.contains(suite.name.lowercased()) {
    runner.runSuite(suite)
}
if arguments.contains("--self-fail") {
    runner.group("--self-fail") { runner.expect(false, "заведомо проваленная проверка") }
}
exit(runner.finish())
