# Submissions: where Jugglinator gets listed and what to paste

Prepared 2026-11-14 after baseline run 3 (0 of 15 mentions, the name is not in any search index). Order matters: search engines first, then the catalogs the assistants cite.

Legend: **Claude** = can be done from a Claude Code session after a go-ahead; **You** = needs your account or a human at the keyboard.

## 1. Search engines

| What | Who | Status |
|---|---|---|
| IndexNow ping (Bing, Yandex, Seznam, Naver) | Claude | key file `docs/1802e8a35f3242d0aa52711b3d080b35.txt` is ready; ping after it is pushed |
| Bing Webmaster Tools | You | not done |
| Google Search Console | You | not done |

`docs/robots.txt` is not read by crawlers: on a project site it lives at `sefimov.github.io/jugglinator/robots.txt`, and robots.txt only counts at the host root. So the sitemap has to be submitted by hand in both consoles.

Bing Webmaster Tools (https://www.bing.com/webmasters):

1. Add site `https://sefimov.github.io/jugglinator/`.
2. Verification method "HTML meta tag". Send the `<meta name="msvalidate.01" content="…">` tag to Claude; it goes into `docs/index.html`, then push and press Verify.
3. Sitemaps → submit `https://sefimov.github.io/jugglinator/sitemap.xml`.
4. URL Submission → submit `https://sefimov.github.io/jugglinator/`.

Google Search Console (https://search.google.com/search-console):

1. Add property of type "URL prefix": `https://sefimov.github.io/jugglinator/`.
2. Verification method "HTML tag". Send the `<meta name="google-site-verification" content="…">` tag to Claude, same as above.
3. Sitemaps → `sitemap.xml`.
4. URL inspection → `https://sefimov.github.io/jugglinator/` → Request indexing.

IndexNow ping, once the key file is live:

```sh
curl -s -o /dev/null -w '%{http_code}\n' 'https://api.indexnow.org/indexnow?url=https://sefimov.github.io/jugglinator/&key=1802e8a35f3242d0aa52711b3d080b35&keyLocation=https://sefimov.github.io/jugglinator/1802e8a35f3242d0aa52711b3d080b35.txt'
```

200 or 202 means accepted.

## 2. Catalogs

### awesome-mac (jaywcjlove/awesome-mac, 118k stars) — Claude, pull request

Rules read on 2026-11-14: one PR per app, alphabetical order, one-sentence description, the entry synced to `README.md`, `README-zh.md`, `README-ja.md`, `README-ko.md`; AI-assisted PRs are allowed. Section: Utilities → Window Management (AltTab, contexts, rcmd, ShortcutCycle and Open Contexts are there).

PR title: `Add Jugglinator to Window Management (EN/ZH/JA/KO)`

`README.md`, after IntelliDock, before JankyBorders:

```md
* [Jugglinator](https://sefimov.github.io/jugglinator/) - Menu bar task switcher that cycles through a short list of AI chats, Claude Code sessions, Chrome tabs, and Terminal tabs with one hotkey. [![Open-Source Software][OSS Icon]](https://github.com/sefimov/jugglinator) ![Freeware][Freeware Icon]
```

`README-zh.md`, after IntelliDock, before JankyBorders:

```md
* [Jugglinator](https://sefimov.github.io/jugglinator/) - 菜单栏任务切换器，用一个快捷键在选定的 AI 对话、Claude Code 会话、Chrome 标签页和终端标签页之间循环切换。 [![Open-Source Software][OSS Icon]](https://github.com/sefimov/jugglinator) ![Freeware][Freeware Icon]
```

`README-ja.md`, after IntelliDock, before JankyBorders:

```md
* [Jugglinator](https://sefimov.github.io/jugglinator/) - 選んだAIチャット、Claude Codeセッション、Chromeのタブ、ターミナルのタブを1つのホットキーで順に切り替えるメニューバーのタスクスイッチャー。 [![Open-Source Software][OSS Icon]](https://github.com/sefimov/jugglinator) ![Freeware][Freeware Icon]
```

`README-ko.md`, after Flickbar, before KiwiDesk:

```md
* [Jugglinator](https://sefimov.github.io/jugglinator/) - 선택한 AI 채팅, Claude Code 세션, Chrome 탭, 터미널 탭을 단축키 하나로 순환 전환하는 메뉴 막대 작업 전환 도구. [![Open-Source Software][OSS Icon]](https://github.com/sefimov/jugglinator) ![Freeware][Freeware Icon]
```

PR body:

```md
Adds Jugglinator to Window Management in the four README files.

Jugglinator is a free, open source (MIT) menu bar app for macOS 14+. It keeps a short list of tasks (a Claude chat, a Claude Code session, a ChatGPT thread, a Chrome tab, a Terminal tab) and cycles through them with one hotkey, reopening the exact chat or tab instead of the app. It sits next to the window switchers in this section: they switch windows, this one switches to a specific chat or tab inside a window.

- Site: https://sefimov.github.io/jugglinator/
- Source: https://github.com/sefimov/jugglinator

I am the author of the app. The entry was prepared with an AI assistant and follows the alphabetical order and the one-sentence rule.
```

### awesome-claude-code (hesreallyhim/awesome-claude-code, 58k stars) — You, web form only

The rules forbid PRs, `gh` and submissions not made by a human; breaking them gets the account restricted. The repo qualifies under rule (i): first commit 2026-10-27, more than 14 days old, with later commits.

Form: https://github.com/hesreallyhim/awesome-claude-code/issues/new?template=recommend-resource.yml

- Display Name: `Jugglinator`
- Category: `Observability & Monitoring > Session Monitors`
- Link: `https://github.com/sefimov/jugglinator`
- Author Name: `sefimov`
- Author Link: `https://github.com/sefimov`
- Description: `macOS menu bar app that keeps a list of parallel tasks (Claude Code sessions in the Claude desktop app, Claude chats, ChatGPT threads, Chrome and Terminal tabs) and cycles through them with one hotkey, reopening the exact session by its id. A menu bar indicator shows how long the longest-waiting task has waited. Includes a stdio MCP server for listing and switching tasks.`
- Checklist: tick the first five boxes only if they are true for you; **leave the last box unchecked** (it is a trap for people who do not read).

Caveat: one checkbox says "This resource is specific to Claude Code". Jugglinator binds Claude Code sessions by id but also handles ChatGPT and plain tabs, so the maintainer may decline it. Worth one try, not a second one.

### awesome-macOS (iCHAIT/awesome-macOS, 19k stars) — skip

The contribution rules exclude "software whose main purpose is interfacing with generative tools like LLMs, chatbots … including agents", and the PR template makes the author confirm having read that section. A task switcher built around AI chats will most likely be closed. Not worth the attempt.

### AlternativeTo — You (account needed)

https://alternativeto.net → "Add new app". It was cited in 5 of 15 answers in run 3.

- Name: `Jugglinator`
- Website: `https://sefimov.github.io/jugglinator/`
- Short description: `Menu bar task switcher for macOS: one hotkey cycles through your chosen AI chats, Claude Code sessions, Chrome tabs and Terminal tabs.`
- Description: `Jugglinator keeps a short list of the tasks you are working on in parallel and switches between them with one hotkey. A task is bound to an exact thing, not to an app: a Claude chat, a Claude Code session, a ChatGPT thread, a Chrome tab, a Terminal tab, or any other window by title. Each switch reopens that chat or tab, even after the app was restarted. A circle in the menu bar turns yellow, orange and red as the task you have ignored the longest waits 10, 30 and 60 minutes. Tasks can be marked done and are then skipped. A built-in MCP server lets an AI assistant list and switch tasks. No account, no network access, no analytics. Free and open source (MIT), macOS 14 or later, Apple silicon build; not notarized.`
- License: Open Source, Free. Platform: Mac.
- Tags: `window-switcher`, `task-switcher`, `menu-bar-app`, `hotkeys`, `ai-tools`, `productivity`
- Alternative to: AltTab, Contexts, rcmd, HopTab, Witch, ShortcutCycle
- Source code: `https://github.com/sefimov/jugglinator`
- Screenshot: `docs/screenshot.png`

### Product Hunt — You, after the demo GIF exists

Cited in 7 of 15 answers. A launch without a GIF or video wastes the one launch day, so it waits for the GIF, as do Reddit and Show HN.

- Name: `Jugglinator`
- Tagline (60 max): `Cmd-Tab for your parallel AI chats`
- Topics: Mac, Productivity, Developer Tools, Artificial Intelligence, Open Source

## 3. Article

Draft: `promo/devto-article.md`. Publish on dev.to under your account (cited in 5 of 15 answers, indexed fast). The front matter has `published: false`: paste it into the dev.to editor, check the preview, then switch to `true`.

## 4. MCP directories

| Directory | Possible now | How |
|---|---|---|
| punkpeye/awesome-mcp-servers (98k stars) | yes, Claude | PR, one line; check the legend and category in the README at PR time |
| mcpservers.org | yes, You | form at https://mcpservers.org/submit (name, category, description, repo link, contact email); free review within two weeks |
| mcp.so | probably, You | form at https://mcp.so/submit (not verified, the page blocks automated reads) |
| Official MCP Registry | not yet | accepts npm, PyPI, NuGet, Cargo, OCI and MCPB packages only; needs an `.mcpb` bundle attached to a GitHub release, then `mcp-publisher login github` and `mcp-publisher publish` under `io.github.sefimov/jugglinator` |
| Smithery | not yet | also wants an `.mcpb` bundle (not verified directly) |
| Glama | not useful | builds the server in a Linux sandbox; a macOS-only app fails the build and is hidden from search |
| PulseMCP | closed | submissions paused; it says it will import from the official registry |

awesome-mcp-servers entry (category "OS Automation" or the closest productivity one):

```md
- [sefimov/jugglinator](https://github.com/sefimov/jugglinator) 🏠 🍎 - macOS menu bar task switcher with a built-in MCP server: list the user's parallel tasks (AI chats, Claude Code sessions, Chrome and Terminal tabs), switch to one, add the current window, mark tasks done, edit notes.
```

mcpservers.org / mcp.so fields:

- Name: `Jugglinator`
- Description: `MCP server built into the Jugglinator macOS menu bar app. Tools: list_tasks, switch_to_task, add_current_window, mark_done, mark_in_progress, set_note. Local stdio, no network.`
- Repository: `https://github.com/sefimov/jugglinator`
- Category: Productivity (or OS automation)

An `.mcpb` bundle would unlock the official registry, Smithery and later PulseMCP in one go. It is a build task of its own: a manifest plus a launcher that runs `/Applications/Jugglinator.app/Contents/MacOS/Jugglinator --mcp`, attached to the next release.

## 5. Re-run

Two to three weeks after the consoles and awesome-mac are done: all 15 questions in Claude (in batches of four or five, to stay under the search rate limit) and by hand in ChatGPT with search on. First check that a plain web search for "Jugglinator" finds the site; if it does not, the run will be 0 again.
