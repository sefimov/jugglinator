import Foundation

/// Набор проверок одной области. Каждая область — свой тип в своей папке.
protocol CheckSuite {
    static var name: String { get }
    static func run(_ c: CheckRunner)
}

/// Минимальный исполнитель проверок (XCTest и Swift Testing на Command Line Tools недоступны).
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

    /// Группа связанных проверок; брошенная ошибка считается провалом.
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

    /// Итог: печатает сводку и возвращает код выхода (0 — всё прошло).
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
