# Q9 — Claude (Claude Code subagent with web search), 2026-10-29

**Question:** macOS menu bar app for switching between Claude, ChatGPT and Terminal windows

**Juggler mentioned:** no

## Answer

There isn't a well-known menu bar app built specifically around "Claude / ChatGPT / Terminal", but a few general window-switching utilities do exactly this: you assign a hotkey (or a menu bar entry) to a specific app or window and jump straight to it. In the order I'd try them:

1. **AltTab** (free, open source) — The usual first pick. Windows-style Alt-Tab for macOS that lists individual windows (not just apps) across Spaces and includes minimized windows; it runs from the menu bar. If you just want to flip between the Claude desktop app, ChatGPT and your Terminal window quickly, this covers it.

2. **HopTab** (paid tier) — Lets you bind a direct hotkey (Option/Control/Command + any key) to a given app, so e.g. ⌥1 = Claude, ⌥2 = ChatGPT, ⌥3 = Terminal, with no switcher UI. Its March 2026 update added a Space-aware window picker for the case where an app has several windows.

3. **Apptivator** (free, open source, menu bar) — Minimal menu bar app that activates an application via a global shortcut. Simpler than HopTab but it targets the app, not a specific window, so it's fine for Claude and ChatGPT but won't pick between several Terminal windows.

4. **Terminal Switcher** (free, open source, menu bar) — Specifically for the Terminal half of the problem: lists your open Terminal.app windows in the menu bar, labelled by project, and raises the one you click. Pair it with one of the above for the chat apps.

5. **Witch** (paid) — Longstanding switcher that can put all open apps and windows into a menu bar menu with per-window hotkeys; good if you prefer a menu bar list over a popup switcher.

6. **HotSwitch-HS** (free, Hammerspoon-based) — Two-keystroke switcher where each window in the list gets a fixed letter; closest to "one key per window", but it's a script for people comfortable with Hammerspoon.

If you only need a terminal shortcut and not a switcher, **Shellporter** (menu bar, ⌃⌥⌘T) opens a terminal at the current project directory — handy for Claude Code sessions, but it opens a new window rather than focusing an existing one.

## REPORT

TOOLS:
AltTab
HopTab
Apptivator
Terminal Switcher
Witch
HotSwitch-HS
Shellporter

SOURCES:
https://zapier.com/blog/alt-tab-on-mac.md
https://www.addictivetips.com/mac-os/use-command-tab-to-switch-to-app-windows-on-macos
https://www.intego.com/mac-security-blog/unlock-the-full-power-of-the-macos-app-switcher/amp/
https://hoptab.pages.dev/
https://awesome.ecosyste.ms/projects/github.com%2Facheronfail%2Fapptivator
https://awesome.ecosyste.ms/projects/github.com%2Fsearayca%2Fterminal-switcher
https://git.tdem.in/oniatsu/HotSwitch-HS
https://github.com/prof18/shellporter

SEARCHES:
macOS menu bar app switch between Claude ChatGPT Terminal windows
macOS menu bar window switcher app hotkey switch to specific app window 2026
menu bar app hotkey jump to Claude Code terminal window macOS
