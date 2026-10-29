import Darwin
import Foundation
import JugglerCore

/// `Juggler --mcp`: the stdio MCP server that Claude Desktop, Claude Code and Codex launch.
///
/// It is a relay: lines from stdin go to the running app's Unix socket, the app's answers go to stdout.
/// While the app is not running (or its MCP server is off) the relay answers `initialize`, `ping` and
/// `tools/list` itself and turns every `tools/call` into a tool error that says how to turn the server on,
/// so the client still sees the tools and the user gets a clear message. The connection is retried on
/// every request, so starting Juggler later just works.
final class MCPStdioBridge: @unchecked Sendable {
    private let socketPath: String
    private let local: MCPRequestHandler
    private let lock = NSLock()
    private var socketFD: Int32 = -1
    /// Ids of requests forwarded to the app and not answered yet (as JSON text, e.g. `1` or `"a"`).
    private var pending: Set<String> = []
    private let output = SerialOutput()

    init(socketPath: String, serverVersion: String) {
        self.socketPath = socketPath
        self.local = MCPRequestHandler(backend: nil, serverVersion: serverVersion)
    }

    /// Runs until stdin closes. Exit code 0.
    static func run(socketPath: String, serverVersion: String) -> Int32 {
        // A client that closed its end must not kill us with SIGPIPE; writes fail instead.
        signal(SIGPIPE, SIG_IGN)
        let bridge = MCPStdioBridge(socketPath: socketPath, serverVersion: serverVersion)
        bridge.log("Juggler MCP relay started, socket \(socketPath)")
        while let line = readLine(strippingNewline: true) {
            bridge.handle(line)
        }
        // stdin closed: let the app answer what is still in flight (a shell pipe closes stdin right after writing).
        bridge.waitForPending(timeout: 10)
        bridge.disconnect(reason: nil)
        bridge.log("stdin closed, exiting")
        return 0
    }

    /// Blocks until every forwarded request has been answered, the app disconnects, or `timeout` passes.
    func waitForPending(timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock()
            let waiting = socketFD >= 0 && !pending.isEmpty
            lock.unlock()
            guard waiting else { return }
            usleep(20_000)
        }
    }

    func handle(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if connectIfNeeded() {
            let id = JSONRPC.requestID(of: trimmed)?.text()
            lock.lock()
            if let id { pending.insert(id) }
            let fd = socketFD
            lock.unlock()
            if fd >= 0, UnixSocket.writeLine(fd, trimmed) { return }
            // The app went away between connect and write: answer locally.
            disconnect(reason: "write failed")
            lock.lock()
            if let id { pending.remove(id) }
            lock.unlock()
        }
        if let response = local.handle(line: trimmed) {
            output.write(response)
        }
    }

    /// `true` when connected to the app (possibly just now).
    private func connectIfNeeded() -> Bool {
        lock.lock()
        if socketFD >= 0 {
            lock.unlock()
            return true
        }
        guard let fd = UnixSocket.connect(path: socketPath) else {
            lock.unlock()
            return false
        }
        socketFD = fd
        lock.unlock()
        log("connected to Juggler")
        let thread = Thread { [weak self] in self?.pump(fd) }
        thread.name = "com.sefimov.juggler.mcp.relay"
        thread.start()
        return true
    }

    /// Socket → stdout. Ends when the app closes the connection.
    private func pump(_ fd: Int32) {
        let reader = UnixSocket.LineReader()
        while let line = reader.next(from: fd) {
            if let id = JSONRPC.requestID(of: line)?.text() {
                lock.lock()
                pending.remove(id)
                lock.unlock()
            }
            output.write(line)
        }
        lock.lock()
        let stillCurrent = socketFD == fd
        lock.unlock()
        if stillCurrent { disconnect(reason: "Juggler closed the connection") }
    }

    /// Drops the connection; requests still in flight get an error so the client does not hang.
    private func disconnect(reason: String?) {
        lock.lock()
        let fd = socketFD
        socketFD = -1
        let unanswered = pending
        pending = []
        lock.unlock()
        if fd >= 0 { close(fd) }
        if let reason { log("disconnected: \(reason)") }
        for id in unanswered {
            let error = JSONRPCError(code: -32000, message: "Juggler quit or turned its MCP server off while the request was in flight. Try again.")
            output.write(JSONRPC.errorResponse(id: JSONValue(text: id), error: error).text())
        }
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("[juggler-mcp] \(message)\n".utf8))
    }
}

/// stdout writes from the stdin thread and the relay thread, one line at a time.
private final class SerialOutput: @unchecked Sendable {
    private let lock = NSLock()

    func write(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        var bytes = Array(line.utf8)
        bytes.append(0x0A)
        bytes.withUnsafeBufferPointer { buffer in
            _ = fwrite(buffer.baseAddress, 1, buffer.count, stdout)
        }
        fflush(stdout)
    }
}
