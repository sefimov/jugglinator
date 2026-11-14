---
title: How to switch between ChatGPT and Claude chats on a Mac with one hotkey
published: false
description: Cmd-Tab switches apps, not chats. Here is what works for jumping between specific AI chats, Claude Code sessions and tabs on macOS, and the small open source app I wrote for it.
tags: macos, ai, productivity, opensource
cover_image: https://sefimov.github.io/jugglinator/screenshot.png
---

I usually have five or six things running at once: three Claude Code sessions on three branches, a ChatGPT thread with a spec, a Claude chat with a design review, a Terminal tab with the tests. Every one of them stops and waits for me at some point, and I kept finding a session that had been waiting for an hour.

The obvious tools do not solve this, because they switch the wrong thing.

## Why Cmd-Tab and window switchers do not help

- **Cmd-Tab** switches apps. Three Claude Code sessions are one app.
- **Window switchers** such as AltTab, Contexts or rcmd switch windows or apps. Two sessions in the Claude desktop app are the same window, and two ChatGPT threads look identical in a list of windows.
- **Hotkey tools** such as Hammerspoon, Keyboard Maestro or BetterTouchTool can focus a window by title or run an AppleScript that selects a Chrome tab by URL. That works for tabs, but there is no script that says "open this ChatGPT thread" or "this Claude Code session", and you have to maintain the scripts as the chats change.
- **Agent session managers** such as cmux or Claude Squad work if all your agents live in one terminal. Mine do not: some are in the Claude desktop app, some in ChatGPT, some in a browser.

What I wanted was a short list of today's tasks, where a task is one exact chat, session or tab, and one key to go to the next one.

## What a "task" has to be bound to

A window title is not enough: titles change and several chats share a window. The binding has to be the identifier the app itself uses:

| Where the task lives | What identifies it |
|---|---|
| Claude desktop chat | the chat UUID, opened through a `claude://` link |
| Claude Code session in the Claude desktop app | the session id |
| ChatGPT desktop thread | the thread id from ChatGPT's local thread index |
| Google Chrome tab | the tab id, then the URL |
| Terminal.app tab | the tty of the tab |
| Anything else (Cursor, VS Code, iTerm2, Safari) | the window title |

With that, "switch to task 3" can reopen the right chat even after the app was restarted.

## Jugglinator

I wrote a menu bar app that does this and nothing else: [Jugglinator](https://sefimov.github.io/jugglinator/). It is free and open source (MIT), written in Swift with no dependencies, for macOS 14 and later.

How it works:

- **Control-Option-Tab** in any window adds it to the list as a task. The same key removes it.
- **Control-Tab** goes to the next task, **Control-Shift-Tab** to the previous one, in a fixed 1 → 2 → 3 → 1 order. A small card shows the task number, its title and how long you were away.
- **Control-§** (Control-` on an ANSI keyboard) marks a task done; done tasks are skipped.
- A circle in the menu bar goes from green to yellow, orange and red as the task you have ignored the longest waits 10, 30 and 60 minutes. Hover it to see which one that is.

It also has a small MCP server, off by default. When it is on, Claude Desktop, Claude Code or Codex can list your tasks, switch to one, add the current window and mark tasks done.

It has no account, no network code and no analytics. It reads ChatGPT's local thread index and Claude Code's local session files to get ids and titles, and stores its own list in `~/Library/Application Support/Jugglinator/tasks.json`.

## Limits

- The release build is for Apple silicon and is not notarized, because I do not have a paid Apple Developer account. On first launch macOS asks you to confirm in System Settings → Privacy & Security → "Open Anyway". On Intel, build from source.
- It needs the Accessibility permission, and Automation for Chrome and Terminal. It asks only when a binding needs it.
- Deep bindings exist for Claude desktop, ChatGPT desktop, Chrome and Terminal.app. Other apps are matched by window title, so two windows with the same title cannot be told apart.
- It does not detect that an agent has finished. The circle measures how long since you last visited a task, not the agent's state.

## If your setup is different

- All sessions are Claude Code in a terminal such as iTerm2, Kitty or WezTerm: look at Juggler by nielsmadan (a different project with a similar name) or cctop; both know which CLI session is waiting for input.
- You only need windows, not chats: AltTab is free and does that well.
- You only need one Chrome tab on a key: an AppleScript bound in Hammerspoon or Raycast is enough.

## Links

- Site: https://sefimov.github.io/jugglinator/
- Source and releases: https://github.com/sefimov/jugglinator

If you juggle AI chats differently, I would like to hear how.
