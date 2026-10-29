import Foundation

/// A set of checks for one area. Each area is its own type in its own folder.
protocol CheckSuite {
    static var name: String { get }
    static func run(_ c: CheckRunner)
}

/// Minimal check runner (XCTest and Swift Testing are unavailable with Command Line Tools).
final class CheckRunner {
    private(set) var passed = 0
    private(set) var failures: [String] = []
    private var suite = ""
    private var group = ""
    private let verbose: Bool

    init(verbose: Bool) {
        self.verbose = verbose
    }

    var total: Int { passed + failures.count }

    func runSuite(_ type: CheckSuite.Type) {
        suite = type.name
        let before = total
        type.run(self)
        let count = total - before
        print("• \(type.name): \(count) проверок")
        suite = ""
        group = ""
    }

    /// A group of related checks; a thrown error counts as a failure.
    func group(_ name: String, _ body: () throws -> Void) {
        group = name
        do {
            try body()
        } catch {
            fail("ошибка: \(error)", file: #fileID, line: #line)
        }
        group = ""
    }

    func expect(_ condition: @autoclosure () -> Bool, _ name: String, file: StaticString = #fileID, line: UInt = #line) {
        if condition() {
            pass(name)
        } else {
            fail(name, file: file, line: line)
        }
    }

    func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ name: String, file: StaticString = #fileID, line: UInt = #line) {
        if actual == expected {
            pass(name)
        } else {
            fail("\(name): получено \(String(reflecting: actual)), ожидалось \(String(reflecting: expected))", file: file, line: line)
        }
    }

    func expectNil<T>(_ value: T?, _ name: String, file: StaticString = #fileID, line: UInt = #line) {
        if let value {
            fail("\(name): ожидался nil, получено \(String(reflecting: value))", file: file, line: line)
        } else {
            pass(name)
        }
    }

    /// Summary: prints the totals and returns the exit code (0 — everything passed).
    func finish() -> Int32 {
        if failures.isEmpty {
            print("Все проверки прошли: \(passed)")
            return 0
        }
        print("\nПровалено \(failures.count) из \(total):")
        failures.forEach { print("  ✗ \($0)") }
        return 1
    }

    private var prefix: String {
        [suite, group].filter { !$0.isEmpty }.joined(separator: " / ")
    }

    private func pass(_ name: String) {
        passed += 1
        if verbose { print("  ✓ \(prefix): \(name)") }
    }

    private func fail(_ name: String, file: StaticString, line: UInt) {
        failures.append("\(prefix): \(name) (\(file):\(line))")
    }
}
