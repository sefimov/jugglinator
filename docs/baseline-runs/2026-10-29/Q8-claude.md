# Q8 — Claude (Claude Code subagent with web search), 2026-10-29

**Question:** Is there a tool that shows which AI chat I have been ignoring the longest?

**Juggler mentioned:** no

## Answer

Short answer: there is no polished, cross-platform tool that explicitly ranks your AI chats by "how long you have left it hanging". The closest things depend on where your chats live:

1. **bliptracker (Chrome extension, claude.ai only)** – The best match for regular Claude.ai chats. It marks each conversation with a red "waiting on you" or green "done" prefix (also visible in the mobile app) and the toolbar icon opens a "waiting on you" queue you can jump into. It works by adding a short instruction to your Claude profile so Claude ends replies with a status marker; it relies on undocumented claude.ai endpoints, so it can break, and I did not see an explicit oldest-first sort.

2. **Claude Code agent view (built in)** – If the "chats" are Claude Code sessions, the built-in agent view lists sessions that need your input along with when you last interacted with each, so you can see at a glance which one has waited longest. Nothing to install.

3. **CCManager (CLI)** – A terminal session manager for Claude Code and other coding agents (Codex, Gemini CLI) that tags every session as waiting / busy / idle and has status-change hooks for notifications. Good if you run many parallel agents, but it does not cover ChatGPT or web chats.

4. **cove / Agent Deck / claudectl** – Similar terminal dashboards (tmux sidebar, multi-agent dashboard, status-and-cost monitor) that show which sessions are waiting for input. Pick one based on whether you live in tmux.

5. **Lantern Reply or LLMinder (Chrome extensions, ChatGPT + Claude)** – These do the inverse: they notify you when ChatGPT or Claude finishes answering in a background tab. They do not keep a list of chats you owe a reply to, but they stop chats from being forgotten in the first place.

For ChatGPT web chats specifically I found nothing that tracks "waiting on you" age; the practical workaround is ChatGPT's sidebar order (most recently active on top, so the bottom of the list is what you have ignored longest).

## REPORT

TOOLS:
bliptracker
Claude Code agent view
CCManager
cove
Agent Deck
claudectl
Lantern Reply
LLMinder

SOURCES:
https://chromewebstore.google.com/detail/bliptracker/dhbhcgiohdpemjhlcmldipoioafeeemj
https://chromewebstore.google.com/detail/lantern-reply/bchiibllkdllfidhjedcbbkbbefbcila
https://www.producthunt.com/products/llminder-ai-workflow-notifications/launches
https://claude.com/blog/agent-view-in-claude-code
https://cdn.jsdelivr.net/npm/ccmanager@4.1.18/README.md
https://docs.rs/crate/cove-cli/0.5.2/source/README.md
https://dev.to/asheshgoplani/how-to-manage-multiple-claude-code-gemini-and-codex-sessions-in-one-terminal-1dci
https://nimbalyst-website.pages.dev/blog/best-session-managers-for-claude-code-and-codex/

SEARCHES:
app that tracks unanswered AI chats ChatGPT Claude conversations waiting on me oldest
tool to manage multiple AI chat sessions Claude Code ChatGPT which one is waiting for input longest
bliptracker Chrome extension Claude chats "waiting on you"
