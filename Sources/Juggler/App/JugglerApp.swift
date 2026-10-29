import AppKit
import JugglerCore
import SwiftUI

/// Entry point. Command-line flags are handled before SwiftUI starts:
/// - `--self-test` — self-test of all components without windows or permission prompts;
/// - `--probe-frontmost` — print JSON with the frontmost window context (BIND);
/// - `--mcp` — stdio MCP server for AI assistants, relayed to the running app (MCP).
@main
enum JugglerEntry {
    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains(MCPConfig.flag) {
            // A plain stdio process launched by Claude Desktop or Claude Code: no AppKit, no windows.
            exit(MCPModule.runStdioBridge())
        }
        if arguments.contains("--self-test") {
            exit(SelfTest.run())
        }
        if arguments.contains("--probe-frontmost") {
            exit(BindModule.probeFrontmost(arguments: arguments))
        }
        JugglerApp.main()
    }
}

/// Menu bar app. The scenes (menu bar and settings) are built by UI in `UIModule.scenes`.
struct JugglerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        UIModule.scenes(environment: AppEnvironment.shared)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Without .app and LSUIElement (`swift run Juggler`) we hide the Dock icon manually.
        NSApp.setActivationPolicy(.accessory)
        AppEnvironment.shared.start()
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        AppEnvironment.shared.stop()
    }
}
