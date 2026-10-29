# Q6 — Claude (Claude Code subagent with web search), 2026-10-29

**Question:** How to jump to a specific Chrome tab with a global keyboard shortcut on macOS

**Juggler mentioned:** no

## Answer

macOS has no built-in way to jump to a specific Chrome tab from another app. Chrome's own Cmd+1…Cmd+8 (tab by position) and Cmd+9 (last tab) only work while Chrome is frontmost. To get a truly global shortcut you need a macro/automation tool that drives Chrome via AppleScript/JXA. Here is what I'd recommend, in order:

1. **Keyboard Maestro** (paid, ~$36). The most reliable route: create a macro with a Hot Key trigger that runs a short AppleScript looping over Chrome's windows and tabs, activating the first tab whose URL (or title) contains a given string, and falling back to an "Open URL" action if nothing matches. A ready-made "Chrome Tab Switcher/Launcher" macro on the KM forum does exactly this (triggered from Stream Deck via KM Link, but the same macro can be given a hotkey trigger). One macro per site/tab, each bound to its own shortcut.

2. **Hammerspoon** (free, open source, Lua). Bind a global hotkey with `hs.hotkey.bind` that runs the same AppleScript/JXA tab-search via `hs.osascript`. Fully scriptable and free, but you write the config yourself; the bundled AppWindowSwitcher Spoon only switches Chrome windows, not tabs, so the tab logic has to be your own script.

3. **Raycast** (free). Its built-in "Switch Windows" command can be given a global hotkey and lets you type part of a window title and press Enter to bring it forward; it operates on windows, not individual tabs, so it only works reliably if the tab you want is the active one in its window (or you keep that page in its own window). Raycast's Quicklinks with hotkeys can open a URL, but will open a new tab rather than focusing an existing one.

4. **BetterTouchTool** (paid). Same idea as Keyboard Maestro: assign a global keyboard shortcut to a "Run AppleScript" action containing the tab-search script. A good choice if you already own it.

5. **Alfred** (free, Powerpack needed for workflows). Workflows with a hotkey trigger running an AppleScript can do the same; I didn't find an official up-to-date Chrome-tab workflow in this pass, so you'd likely adapt one.

6. **Quick Switch** (Chrome extension). Launched by a global shortcut (set in chrome://extensions/shortcuts), it jumps to pinned tabs across windows; limited to pinned tabs, and Chrome extension "global" shortcuts need Chrome to be running.

Whichever tool you pick, macOS will prompt you to allow it to control Chrome (System Settings > Privacy & Security > Automation / Accessibility) the first time the script runs.

## REPORT

TOOLS:
Keyboard Maestro
Hammerspoon
Raycast
BetterTouchTool
Alfred
Quick Switch (Chrome extension)

SOURCES:
https://forum.keyboardmaestro.com/t/chrome-tab-switcher-launcher-v1-0-universal-km-link-macro-for-stream-deck/51711
https://manual.raycast.com/navigation.md
https://www.hammerspoon.org/Spoons/AppWindowSwitcher.html
https://chrome.google.com/webstore/detail/quick-switch/pliiecepjdknmcninijkgcboekaomphi/reviews?hl=en

SEARCHES:
macOS global keyboard shortcut switch to specific Chrome tab
Mac app hotkey jump to Chrome tab by name Raycast Alfred extension
switch to Chrome tab from any app global hotkey macOS Keyboard Maestro Hammerspoon script

(Note from the agent: the first search returned a rate-limit error and produced no results; the other two succeeded.)
