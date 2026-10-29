import Foundation

// JSON-RPC 2.0, the part MCP needs: one request or notification per line, one response per request.

/// An incoming request (`id` present) or notification (`id == nil`).
public struct JSONRPCRequest: Equatable, Sendable {
    /// `null`, a number or a string; `nil` for a notification.
    public var id: JSONValue?
    public var method: String
    public var params: JSONValue?

    public init(id: JSONValue?, method: String, params: JSONValue? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }

    public var isNotification: Bool { id == nil }
}

/// A JSON-RPC error: code, message and optional data.
public struct JSONRPCError: Error, Equatable, Sendable {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603

    public var code: Int
    public var message: String
    public var data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    public static func methodNotFound(_ method: String) -> JSONRPCError {
        JSONRPCError(code: methodNotFound, message: "Method not found: \(method)")
    }

    public static func invalidParams(_ message: String) -> JSONRPCError {
        JSONRPCError(code: invalidParams, message: message)
    }

    public var json: JSONValue {
        var object: [String: JSONValue] = ["code": .number(Double(code)), "message": .string(message)]
        if let data { object["data"] = data }
        return .object(object)
    }
}

public enum JSONRPC {
    /// Parses one message. A batch (array) is rejected: MCP 2025-06-18 does not use batches.
    public static func parse(_ text: String) -> Result<JSONRPCRequest, JSONRPCError> {
        guard let value = JSONValue(text: text) else {
            return .failure(JSONRPCError(code: JSONRPCError.parseError, message: "Parse error: the line is not valid JSON"))
        }
        return parse(value)
    }

    public static func parse(_ value: JSONValue) -> Result<JSONRPCRequest, JSONRPCError> {
        guard let object = value.objectValue else {
            return .failure(JSONRPCError(code: JSONRPCError.invalidRequest, message: "Invalid request: expected a JSON object"))
        }
        guard object["jsonrpc"]?.stringValue == "2.0" else {
            return .failure(JSONRPCError(code: JSONRPCError.invalidRequest, message: "Invalid request: \"jsonrpc\" must be \"2.0\""))
        }
        guard let method = object["method"]?.stringValue, !method.isEmpty else {
            return .failure(JSONRPCError(code: JSONRPCError.invalidRequest, message: "Invalid request: \"method\" must be a string"))
        }
        let id = object["id"]
        if let id, id.stringValue == nil, id.doubleValue == nil, !id.isNull {
            return .failure(JSONRPCError(code: JSONRPCError.invalidRequest, message: "Invalid request: \"id\" must be a string, a number or null"))
        }
        if let params = object["params"], params.objectValue == nil, params.arrayValue == nil, !params.isNull {
            return .failure(JSONRPCError(code: JSONRPCError.invalidRequest, message: "Invalid request: \"params\" must be an object or an array"))
        }
        return .success(JSONRPCRequest(id: id, method: method, params: object["params"]))
    }

    /// The id of a request line without validating the rest (`nil` for a notification or garbage).
    public static func requestID(of text: String) -> JSONValue? {
        guard let value = JSONValue(text: text), let id = value["id"], !id.isNull else { return nil }
        return id
    }

    public static func response(id: JSONValue?, result: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": id ?? .null, "result": result]
    }

    public static func errorResponse(id: JSONValue?, error: JSONRPCError) -> JSONValue {
        ["jsonrpc": "2.0", "id": id ?? .null, "error": error.json]
    }
}
