import Darwin
import Foundation
import JugglerCore
import os

let mcpLog = Logger(subsystem: JugglerLog.subsystem, category: "mcp")

/// Accepts MCP clients (`Juggler --mcp` relays) on a Unix socket. Each connection gets its own
/// `MCPRequestHandler` and a reader thread; every request is handled on the main thread, where
/// the model, the switcher and BIND live, and the response goes back on the same connection.
final class MCPSocketServer: @unchecked Sendable {
    let path: String
    private let makeHandler: @MainActor () -> MCPRequestHandler
    private let acceptQueue = DispatchQueue(label: "com.sefimov.juggler.mcp.accept")
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?
    private var clients: Set<Int32> = []

    init(path: String, makeHandler: @escaping @MainActor () -> MCPRequestHandler) {
        self.path = path
        self.makeHandler = makeHandler
    }

    var isListening: Bool {
        lock.lock()
        defer { lock.unlock() }
        return listenFD >= 0
    }

    var clientCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return clients.count
    }

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard listenFD < 0 else { return }
        let fd = try UnixSocket.listen(path: path)
        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.resume()
        self.source = source
    }

    /// Closes the listening socket, removes the socket file and drops the connections
    /// (their reader threads see end of stream and exit).
    func stop() {
        lock.lock()
        let fd = listenFD
        listenFD = -1
        let source = self.source
        self.source = nil
        let open = clients
        lock.unlock()
        source?.cancel()
        if fd >= 0 {
            close(fd)
            unlink(path)
        }
        for client in open { shutdown(client, SHUT_RDWR) }
    }

    private func acceptPending() {
        while true {
            lock.lock()
            let listening = listenFD
            lock.unlock()
            guard listening >= 0 else { return }
            let fd = accept(listening, nil, nil)
            if fd < 0 {
                if errno == EINTR { continue }
                return // EAGAIN: nothing more pending
            }
            UnixSocket.prepareStream(fd)
            lock.lock()
            clients.insert(fd)
            lock.unlock()
            let thread = Thread { [weak self] in self?.serve(fd) }
            thread.name = "com.sefimov.juggler.mcp.client"
            thread.start()
        }
    }

    private func serve(_ fd: Int32) {
        mcpLog.info("MCP client connected")
        let handler = DispatchQueue.main.sync { MainActor.assumeIsolated { makeHandler() } }
        let reader = UnixSocket.LineReader()
        while let line = reader.next(from: fd) {
            // The handler touches the model and BIND: main thread only.
            let response = DispatchQueue.main.sync { handler.handle(line: line) }
            if let response, !UnixSocket.writeLine(fd, response) { break }
        }
        lock.lock()
        clients.remove(fd)
        lock.unlock()
        close(fd)
        mcpLog.info("MCP client disconnected")
    }
}
