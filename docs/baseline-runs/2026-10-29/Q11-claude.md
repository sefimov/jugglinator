# Q11 — Claude (Claude Code subagent with web search), 2026-10-29

**Question:** Open source macOS window switcher that remembers a specific chat or tab, not just the app

**Juggler mentioned:** no

## Answer

Short version: there is no well-known open source macOS switcher that natively bookmarks a specific chat or tab inside an app. Window switchers see windows; tabs and chats live inside a window, so the tools that get closest either read tab titles via browser scripting or rely on you scripting a deep link. Here is what I would try, in order:

1. macOS Quick Window Switcher (AndrewMagdy, GitHub) — a Spotlight-style search over open windows that also indexes browser tabs in Chrome and Safari by title, so typing part of a tab name jumps to that tab. It only covers those two browsers, has no license listed and looks lightly maintained, so test it before relying on it.

2. unmarked (shalomb, GitHub) — a vim-marks / harpoon-style tool: `unmarked mark f` tags the current window, `unmarked summon f` brings it back. It works at the window level, not the tab or chat level, and needs yabai + skhd (Hammerspoon optional), so it suits people already in that tiling-WM ecosystem.

3. AltTab (lwouis, GitHub) — the most polished open source window switcher for macOS and a good base layer. It lists individual windows with thumbnails across apps, but it cannot target a tab or chat inside a window.

4. Hammerspoon (open source, Lua) — not a switcher out of the box, but the practical way to get exactly what you asked: bind a hotkey that opens a deep link such as `tg://resolve?domain=...` for a Telegram chat or `slack://channel?team=...&id=...` for a Slack channel, or that uses the Accessibility API to find a window/tab by title and focus it.

5. QuicKey (Chrome extension, open source) — if the "tab" part is what matters most, this gives a fast fuzzy switcher over all Chrome tabs across windows, and can be combined with any of the above for the window layer.

Honest caveat: for chats in Telegram/Slack/Messages, none of these remember a conversation automatically; the deep-link approach via Hammerspoon (or the apps' own in-app ⌘K switchers) is the realistic route today.

## REPORT

TOOLS:
macOS Quick Window Switcher
unmarked
AltTab
Hammerspoon
QuicKey

SOURCES:
https://github.com/AndrewMagdy/macOS-Quick-Window-Switcher
https://github.com/shalomb/unmarked
https://www.github.com/lwouis/alt-tab-macos/wiki
https://chrome.google.com/webstore/detail/quickey-%E2%80%93-the-quick-tab-s/ldlghkoiihaelfnggonhjnfiabmaficg
https://awesome.ecosyste.ms/projects/github.com%2Fxcodebuild%2Fcerebro-mac-switch-window
https://help.nuilab.org/systems/mattermost/keyboard-shortcuts/

SEARCHES:
open source macOS window switcher switch to specific browser tab or chat
macOS hotkey jump to specific Telegram chat or Slack channel open source app
macOS app bookmark a window or browser tab with hotkey and return to it later github
