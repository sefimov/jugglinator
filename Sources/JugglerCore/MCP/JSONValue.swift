import Foundation

/// A JSON document as a value: what `JSONSerialization` returns, but typed.
///
/// Used by the MCP server (JSON-RPC messages, tool schemas and results) so that the protocol
/// logic can be checked from JugglerChecks without `Any` casts everywhere.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: - Reading

    public var isNull: Bool { if case .null = self { return true } else { return false } }

    public var boolValue: Bool? { if case .bool(let b) = self { return b } else { return nil } }

    public var doubleValue: Double? { if case .number(let d) = self { return d } else { return nil } }

    /// An integral number (`3`, not `3.5`) as `Int`.
    public var intValue: Int? {
        guard case .number(let d) = self, d.isFinite, d == d.rounded(), abs(d) < 9_007_199_254_740_992 else { return nil }
        return Int(d)
    }

    public var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }

    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a } else { return nil } }

    public var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o } else { return nil } }

    /// Member of an object (`nil` for a missing key or a non-object).
    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    // MARK: - Bridging to JSONSerialization

    /// From a `JSONSerialization` object. `nil` for a value that is not JSON (e.g. `Date`).
    public init?(any: Any) {
        switch any {
        case is NSNull:
            self = .null
        case let number as NSNumber:
            // `true`/`false` come back as NSNumber too; distinguish them by the CF type.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            var out: [JSONValue] = []
            out.reserveCapacity(array.count)
            for element in array {
                guard let value = JSONValue(any: element) else { return nil }
                out.append(value)
            }
            self = .array(out)
        case let dictionary as [String: Any]:
            var out: [String: JSONValue] = [:]
            for (key, element) in dictionary {
                guard let value = JSONValue(any: element) else { return nil }
                out[key] = value
            }
            self = .object(out)
        default:
            return nil
        }
    }

    /// A `JSONSerialization` object. Integral numbers become `Int` so they serialize as `3`, not `3.0`.
    public var any: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let d):
            if let i = intValue { return i }
            return d
        case .string(let s): return s
        case .array(let a): return a.map(\.any)
        case .object(let o): return o.mapValues(\.any)
        }
    }

    /// Parses JSON text. `nil` if the text is not valid JSON.
    public init?(data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let value = JSONValue(any: object) else { return nil }
        self = value
    }

    public init?(text: String) {
        self.init(data: Data(text.utf8))
    }

    /// Serialized JSON with sorted keys (stable output for checks and logs). `pretty` adds line breaks.
    public func data(pretty: Bool = false) -> Data {
        var options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        if pretty { options.insert(.prettyPrinted) }
        // Every case above maps to a valid JSON object, so serialization cannot fail.
        return (try? JSONSerialization.data(withJSONObject: any, options: options)) ?? Data()
    }

    public func text(pretty: Bool = false) -> String {
        String(decoding: data(pretty: pretty), as: UTF8.self)
    }
}

// Literals, so schemas and results read like JSON.
extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(nilLiteral: ()) { self = .null }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

extension JSONValue {
    /// `.string` for a value, `.null` for `nil`.
    public static func string(_ value: String?) -> JSONValue {
        value.map(JSONValue.string) ?? .null
    }

    /// `.number` for a value, `.null` for `nil`.
    public static func int(_ value: Int?) -> JSONValue {
        value.map { .number(Double($0)) } ?? .null
    }
}
