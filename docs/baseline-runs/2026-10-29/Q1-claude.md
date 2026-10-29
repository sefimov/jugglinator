# Q1 — Claude (Claude Code subagent with web search), 2026-10-29

**Question:** How do I switch between multiple Claude Code sessions on a Mac with a hotkey?

**Juggler mentioned:** yes(1), but a DIFFERENT product with the same name: "Juggler" by nielsmadan (juggler-6rl.pages.dev, brew cask nielsmadan/tap/juggler, macOS 15+, ⇧⌘K/J/L/H hotkeys, iTerm2/Kitty/WezTerm). Not sefimov/juggler.

## Answer

It depends on where your sessions live. If they are terminal windows or tabs (the CLI), there is no built-in Claude Code hotkey for jumping between them, so you need either your terminal's own tab shortcuts or a small helper app. If you use the Claude desktop app, it has session-switching shortcuts of its own.

**1. Juggler (menu bar app, free, open source)** — the most direct answer for CLI sessions. It hooks into Claude Code (plus OpenCode, Codex and a few others) and gives you global hotkeys: ⇧⌘K jumps to the next session that is idle/waiting for input, ⇧⌘J goes to the previous one, ⇧⌘L "backburners" the current one so it is skipped, ⇧⌘H brings backburnered sessions back, and ⇧⌘; opens the session monitor. Works with iTerm2, Kitty and WezTerm (tmux/SSH optional), needs macOS 15+; install via `brew install --cask nielsmadan/tap/juggler` or the .dmg from GitHub releases.

**2. cctop (menu bar app)** — a keyboard-first session monitor. A global hotkey overlays numbered badges (1–9) on every running session; press the number to jump to it (in iTerm2 it lands on the specific pane). Good if you prefer "go to session 3" over "go to the next idle one". Supports iTerm2, Ghostty, Warp and others.

**3. Claude desktop app shortcuts** — if you run Claude Code inside the desktop app, Ctrl+Tab switches to the next session; Ctrl+Shift+Tab or ⌘⇧[ is documented for the previous session, though a June 2026 bug report says the backward shortcuts do nothing on macOS while Ctrl+Tab works. Option+Up/Down also moves between sessions in the sidebar in recent builds, and a ⌘1–9 jump-to-session request was closed as resolved; press ⌘/ in the app to see the current shortcut list.

**4. Your terminal's own tab/window shortcuts** — no extra software: ⌘⇧] / ⌘⇧[ (or ⌘1–9) cycle tabs in iTerm2, Terminal.app, Ghostty and Warp; in tmux, `prefix + n/p` or `prefix + 0–9`. Combine with Mantel if you want per-project colors and names so you can tell the windows apart.

**5. Agent Sessions / CodeIsland** — monitors rather than hotkey switchers. Agent Sessions (Rust, macOS-only) lists all running Claude Code sessions in one window; CodeIsland turns the MacBook notch into a control panel and can jump to iTerm2 or Ghostty sessions. Useful if you mostly want an overview and only occasionally click through.

## REPORT

TOOLS:
Juggler (nielsmadan, not sefimov)
cctop
Claude desktop app (built-in shortcuts)
Terminal tab shortcuts (iTerm2/Terminal.app/Ghostty/Warp/tmux) + Mantel
Agent Sessions
CodeIsland

SOURCES:
https://juggler-6rl.pages.dev/
https://feedbagel.com/post/mantel
https://claudeissues.com/issue/61126-feature-desktop-app-jump-directly-to-a-session-tab-by-index-cmd-1-9
https://claudeissues.com/issue/68113-bug-desktop-app-macos-previous-session-shortcuts-ctrl-shift-tab-cmd-shift-do-not
https://claudeissues.com/issue/96517-bug-claude-code-macos-desktop-overrides-system-text-editing-shortcuts-option-up
https://claudeissues.com/issue/45690-feature-add-keyboard-shortcut-for-switching-between-code-sessions-in-claude-desk
https://dev.to/ozan_kak_75bcbab7a8a1/macos-app-to-monitor-all-running-claude-code-sessions-at-once-1jm8
https://nameocean.net/article/managing-multiple-ai-coding-sessions-heres-your-new-superpower/
https://claudepluginhub.com/marketplaces/st0012-cctop
https://dev.to/krisying/i-turned-my-macbooks-notch-into-a-control-center-for-ai-coding-agents-2o57

SEARCHES:
switch between multiple Claude Code sessions Mac hotkey
Claude Code desktop app keyboard shortcuts next session previous session macOS
cctop menubar Claude Code sessions numbered badges hotkey iTerm2 Ghostty
