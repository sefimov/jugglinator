import Foundation
import JugglerCore

/// The "MCP server" setting and the server's lifetime: off by default; when on, the app listens
/// on `mcp.sock` in its data folder from launch until quit. Also provides the config snippets
/// shown in Settings.
@MainActor
final class MCPServerController: ObservableObject {
    enum Status: Equatable {
        case off
        case listening
        /// Localized explanation for Settings.
        case failed(String)
    }

    @Published private(set) var isEnabled: Bool
    @Published private(set) var status: Status = .off

    let socketPath: String
    let serverVersion: String
    private let defaults: UserDefaults
    private let makeBackend: @MainActor () -> MCPTaskBackend
    private var server: MCPSocketServer?

    /// `defaults` and `socketPath` are substituted in the self-test so the real setting and socket are untouched.
    init(defaults: UserDefaults = .standard, socketPath: String, serverVersion: String,
         makeBackend: @escaping @MainActor () -> MCPTaskBackend) {
        self.defaults = defaults
        self.socketPath = socketPath
        self.serverVersion = serverVersion
        self.makeBackend = makeBackend
        self.isEnabled = defaults.bool(forKey: MCPConfig.enabledKey)
    }

    /// The binary MCP clients launch: `/Applications/Jugglinator.app/Contents/MacOS/Jugglinator` from the .app,
    /// the `.build` binary under `swift run`.
    var executablePath: String {
        (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath().path
    }

    var isRunningFromApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var claudeDesktopSnippet: String { MCPConfig.claudeDesktopSnippet(executablePath: executablePath) }
    var claudeCodeCommand: String { MCPConfig.claudeCodeCommand(executablePath: executablePath) }
    var codexSnippet: String { MCPConfig.codexSnippet(executablePath: executablePath) }

    var isListening: Bool { server?.isListening == true }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: MCPConfig.enabledKey)
        isEnabled = enabled
        if enabled { start() } else { stop() }
    }

    /// Called from the composition root after launch.
    func startIfEnabled() {
        if isEnabled { start() }
    }

    func start() {
        guard server == nil else { return }
        let version = serverVersion
        let makeBackend = self.makeBackend
        let server = MCPSocketServer(path: socketPath) {
            MCPRequestHandler(backend: makeBackend(), serverVersion: version)
        }
        do {
            let directory = URL(fileURLWithPath: socketPath).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try server.start()
            self.server = server
            status = .listening
            mcpLog.info("MCP server listening at \(self.socketPath, privacy: .public)")
        } catch {
            let reason = (error as? UnixSocket.SocketError)?.description ?? error.localizedDescription
            status = .failed(loc("Не удалось запустить MCP-сервер: \(reason)"))
            mcpLog.error("MCP server failed to start: \(reason, privacy: .public)")
        }
    }

    func stop() {
        server?.stop()
        server = nil
        status = .off
    }
}
