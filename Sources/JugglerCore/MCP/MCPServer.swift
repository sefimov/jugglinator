import Foundation

/// The MCP (Model Context Protocol) server logic: JSON-RPC over newline-delimited JSON,
/// the `initialize` handshake, `ping`, `tools/list` and `tools/call`.
///
/// Transport-agnostic: the app feeds it lines from a Unix socket, `Jugglinator --mcp` feeds it lines
/// from stdin when the app is not running. One instance per connection (it remembers whether
/// the client has initialized, nothing else).
public final class MCPRequestHandler {
    /// The protocol revision we speak. Older clients that ask for an earlier revision get the one they asked for:
    /// everything we use (tools with `structuredContent`) degrades gracefully.
    public static let protocolVersion = "2025-06-18"
    public static let supportedVersions: Set<String> = ["2025-06-18", "2025-03-26", "2024-11-05"]
    public static let serverName = "jugglinator"

    /// Shown to the assistant after `initialize`: what the server is for.
    public static let instructions = "Jugglinator keeps the user's list of parallel tasks on their Mac: Claude chats, "
        + "Claude Code sessions, ChatGPT threads, Chrome tabs, Terminal tabs and other windows, each bound to the exact "
        + "chat, session, thread or tab. Use list_tasks to see the list and which task is current, switch_to_task to bring "
        + "a task to the front, add_current_window to add the frontmost window, mark_done / mark_in_progress and set_note "
        + "to update a task."

    /// `nil` — the app is not reachable: the handshake still works, tool calls return `unavailableMessage`.
    public let backend: MCPTaskBackend?
    public let serverVersion: String
    public let unavailableMessage: String
    public private(set) var isInitialized = false
    public private(set) var clientInfo: JSONValue?

    public init(backend: MCPTaskBackend?, serverVersion: String,
                unavailableMessage: String = MCPRequestHandler.defaultUnavailableMessage) {
        self.backend = backend
        self.serverVersion = serverVersion
        self.unavailableMessage = unavailableMessage
    }

    public static let defaultUnavailableMessage = "Jugglinator is not running or its MCP server is turned off. "
        + "Open Jugglinator and turn on \"MCP server\" in Settings, then try again."

    /// One line in, at most one line out (`nil` for a notification). Never throws: errors become JSON-RPC errors.
    public func handle(line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch JSONRPC.parse(trimmed) {
        case .failure(let error):
            return JSONRPC.errorResponse(id: JSONRPC.requestID(of: trimmed), error: error).text()
        case .success(let request):
            return handle(request)?.text()
        }
    }

    /// A parsed request → response object (`nil` for a notification).
    public func handle(_ request: JSONRPCRequest) -> JSONValue? {
        if request.method.hasPrefix("notifications/") {
            if request.method == "notifications/initialized" { isInitialized = true }
            return nil
        }
        // A client that sends a request without an id is not following JSON-RPC; answer with a null id anyway.
        switch result(for: request) {
        case .success(let result): return JSONRPC.response(id: request.id, result: result)
        case .failure(let error): return JSONRPC.errorResponse(id: request.id, error: error)
        }
    }

    private func result(for request: JSONRPCRequest) -> Result<JSONValue, JSONRPCError> {
        switch request.method {
        case "initialize":
            let requested = request.params?["protocolVersion"]?.stringValue
            clientInfo = request.params?["clientInfo"]
            let version = requested.flatMap { Self.supportedVersions.contains($0) ? $0 : nil } ?? Self.protocolVersion
            return .success([
                "protocolVersion": .string(version),
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": .string(Self.serverName), "title": "Jugglinator", "version": .string(serverVersion)],
                "instructions": .string(Self.instructions),
            ])

        case "ping":
            return .success([:])

        case "tools/list":
            return .success(["tools": .array(MCPTools.catalog.map(\.json))])

        case "tools/call":
            guard let name = request.params?["name"]?.stringValue else {
                return .failure(.invalidParams("Invalid params: \"name\" (string) is required"))
            }
            guard let backend else {
                return .success(MCPToolResult.error(unavailableMessage).json)
            }
            return .success(MCPTools.call(name, arguments: request.params?["arguments"], backend: backend).json)

        default:
            return .failure(.methodNotFound(request.method))
        }
    }
}
