# Q4 — Claude (Claude Code subagent with web search), 2026-10-29

**Question:** Mac app to keep a short list of open chats and windows and jump between them with one key

**Juggler mentioned:** no

## Answer

What you're describing — a small hand-picked set of windows (a Slack chat, a Telegram chat, a terminal, a browser tab…) each reachable by one keystroke — is a bit niche, so the choices split into "assign a key to a window" tools and more general window switchers. In the order I'd try them:

1. **HotSwitch-HS** (free, MIT; Hammerspoon module) — the closest fit. Open the panel with one trigger key, hit Space on a window and press a letter to register it; from then on `trigger + letter` jumps straight to that window. Keys stay reserved for the windows you registered, so your "short list" is exactly the set of keys you assigned. Needs Hammerspoon installed (and Karabiner-Elements only if you want to hijack ⌘Tab).

2. **HotSwitch** (free, standalone app) — the same idea without Hammerspoon: a global hotkey opens a panel of open windows, each with a key; press it to jump. Less maintained than the Hammerspoon version, so check it works on your macOS first.

3. **Contexts** (~$10, trial) — a polished window-level switcher: a vertical list of all windows where each entry gets a key you can type to jump to it, plus search by typing part of the window title (handy for chat windows whose titles are the chat name). Not a curated list, but fast enough that it feels like one.

4. **WinRes** (free, open source) — a simpler approach: bind a hotkey per app (by bundle ID); pressing it activates the app or cycles its windows. Good if your "chats" live in different apps rather than in multiple windows of one app.

5. **HopTab** (free, open source) — pin a few apps and step through them with Option+Tab. App-level only, so it won't distinguish two chat windows of the same app.

6. **ShortcutCycle** — group apps (e.g. "Chats") and cycle through a group with one key. Also app-level.

Honorable mention: if you already use **Keyboard Maestro** or **Hammerspoon** on their own, a few lines of script (focus window whose title contains "X") will do this with no extra app.

## REPORT

TOOLS:
HotSwitch-HS
HotSwitch
Contexts
WinRes
HopTab
ShortcutCycle
Keyboard Maestro
Hammerspoon

SOURCES:
https://github.com/oniatsu/HotSwitch-HS
https://git.tdem.in/oniatsu/HotSwitch-HS
https://mac.softpedia.com/get/Utilities/HotSwitch.shtml
https://contexts.co/
https://www.howtogeek.com/671085/how-to-switch-between-open-apps-and-windows-on-mac/
https://github.com/mdmitry01/WinRes
https://astro-hacker-news.pages.dev/47474967
https://project-awesome.org/r/xcv58-ShortcutCycle

SEARCHES:
Mac app pin list of windows switch with single hotkey window switcher
macOS app assign hotkey to specific window jump between windows and chats
Contexts app macOS fast window switcher quick switch list
