import AppKit
import JugglerCore
import SwiftUI

/// Settings → "MCP server": the toggle, what it does, and the snippets for Claude Desktop, Claude Code and Codex.
struct MCPSettingsSection: View {
    @ObservedObject var controller: MCPServerController

    var body: some View {
        Section(loc("MCP-сервер")) {
            Toggle(loc("Включить MCP-сервер"), isOn: Binding(
                get: { controller.isEnabled },
                set: { controller.setEnabled($0) }))
            Text(loc("ИИ-ассистенты — Claude Desktop, Claude Code, ChatGPT — смогут видеть список задач, переключаться на задачу, добавлять текущее окно, отмечать задачи сделанными и менять заметки. Работает только на этом Mac, через сокет в папке данных Juggler, без сети."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if case .failed(let message) = controller.status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if controller.isEnabled {
                if !controller.isRunningFromApp {
                    Text(loc("Juggler запущен не из Juggler.app: в примерах ниже путь к текущей сборке."))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SnippetRow(title: loc("Claude Desktop: добавьте в claude_desktop_config.json"), text: controller.claudeDesktopSnippet)
                SnippetRow(title: loc("Claude Code: выполните в Терминале"), text: controller.claudeCodeCommand)
                SnippetRow(title: loc("ChatGPT (Codex): добавьте в ~/.codex/config.toml"), text: controller.codexSnippet)
                LabeledContent(loc("Сокет")) {
                    Text(controller.socketPath)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A caption, a "Copy" button and the snippet in a monospaced box.
private struct SnippetRow: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(loc("Скопировать")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .controlSize(.small)
            }
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        }
    }
}
