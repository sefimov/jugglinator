import Foundation

/// Where the MCP server lives and how clients are told to reach it.
///
/// Transport: the running Jugglinator.app listens on a Unix socket in its data folder
/// (`~/Library/Application Support/Jugglinator/mcp.sock`); `Jugglinator --mcp` is the stdio process that
/// MCP clients launch, and it relays newline-delimited JSON-RPC between stdin/stdout and that socket.
public enum MCPConfig {
    /// `UserDefaults` key of the "MCP server" toggle (off by default).
    public static let enabledKey = "mcpServerEnabled"
    /// The command-line flag that turns the Jugglinator executable into the stdio relay.
    public static let flag = "--mcp"
    public static let socketFileName = "mcp.sock"
    /// Server name in client configs (`claude mcp add jugglinator …`, `"mcpServers": {"jugglinator": …}`).
    public static let serverName = "jugglinator"
    public static let claudeDesktopConfigPath = "~/Library/Application Support/Claude/claude_desktop_config.json"
    public static let codexConfigPath = "~/.codex/config.toml"

    /// `mcp.sock` next to `tasks.json`.
    public static func socketURL(dataDirectory: URL) -> URL {
        dataDirectory.appendingPathComponent(socketFileName)
    }

    /// `sockaddr_un.sun_path` holds 104 bytes including the terminator; a longer path cannot be bound.
    public static let maxSocketPathLength = 103

    public static func isSocketPathUsable(_ path: String) -> Bool {
        path.utf8.count <= maxSocketPathLength
    }

    /// The `mcpServers` entry for Claude Desktop's `claude_desktop_config.json`.
    public static func claudeDesktopSnippet(executablePath: String) -> String {
        let config: JSONValue = [
            "mcpServers": [
                serverName: [
                    "command": .string(executablePath),
                    "args": [.string(flag)],
                ],
            ],
        ]
        return config.text(pretty: true)
    }

    /// `claude mcp add jugglinator -- <executable> --mcp` for Claude Code.
    public static func claudeCodeCommand(executablePath: String) -> String {
        "claude mcp add \(serverName) -- \(shellQuoted(executablePath)) \(flag)"
    }

    /// The `[mcp_servers.jugglinator]` table for ChatGPT desktop / Codex (`~/.codex/config.toml`).
    public static func codexSnippet(executablePath: String) -> String {
        """
        [mcp_servers.\(serverName)]
        command = \(JSONValue.string(executablePath).text())
        args = ["\(flag)"]
        """
    }

    /// Single quotes for a shell unless the path is plain (letters, digits, `/._-`).
    public static func shellQuoted(_ path: String) -> String {
        let plain = path.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "/._-".unicodeScalars.contains($0) }
        if plain, !path.isEmpty { return path }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
