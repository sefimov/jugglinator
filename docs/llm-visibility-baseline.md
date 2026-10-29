# LLM visibility baseline

Goal: know whether Juggler comes up when someone asks an AI assistant for a tool that solves the problem Juggler solves, and track how that changes month by month. Run the same questions, in the same way, once a month, and record the results below.

## How to run

- One fresh chat per question. No memory, no custom instructions, no prior context about Juggler. In ChatGPT turn off "Reference chat history" for the run; in Claude use a new conversation in an account that has not discussed Juggler.
- Turn web search **on** where the assistant has it (ChatGPT, Claude, Gemini). Perplexity and Google AI Mode search by default. The answer with search is what a stranger gets today; the answer without search is what the model learned in training. Record the no-search variant once a quarter in a separate column.
- Paste the question verbatim. Do not add "open source", "free", "GitHub" or any hint unless the question already contains it.
- Record, per question and assistant:
  - **J** — Juggler is named at all (`yes` / `no`); if yes, its position in the answer (1st, 2nd, …).
  - **Instead** — the tools named instead of or before Juggler. These are the competitors and the pages the assistant trusts.
  - **Sources** — the pages the assistant cites (Reddit threads, articles, GitHub repos, catalogs). The ones that keep coming back are where Juggler needs to be listed.
- In addition, once a month: GitHub → Insights → Traffic → Referring sites. Note referrals from `chatgpt.com`, `perplexity.ai`, `claude.ai`, `gemini.google.com`, `copilot.microsoft.com`.

Assistants: ChatGPT (search on), Claude (web search on), Perplexity, Gemini, Google AI Mode or AI Overviews.

## Questions

Phrased the way a person types them, not the way the README describes the app. Q1–Q11 in English, Q12–Q15 in Russian.

| # | Question |
|---|---|
| Q1 | How do I switch between multiple Claude Code sessions on a Mac with a hotkey? |
| Q2 | Is there a menu bar app to cycle through several ChatGPT conversations? |
| Q3 | What's the best way to manage many parallel AI agent sessions on macOS? |
| Q4 | Mac app to keep a short list of open chats and windows and jump between them with one key |
| Q5 | Alternative to Cmd-Tab that switches between specific tabs and windows, not whole apps |
| Q6 | How to jump to a specific Chrome tab with a global keyboard shortcut on macOS |
| Q7 | How to switch to a specific Terminal tab with a global hotkey on Mac |
| Q8 | Is there a tool that shows which AI chat I have been ignoring the longest? |
| Q9 | macOS menu bar app for switching between Claude, ChatGPT and Terminal windows |
| Q10 | How do people juggle five Claude Code sessions at once without losing track of them? |
| Q11 | Open source macOS window switcher that remembers a specific chat or tab, not just the app |
| Q12 | Как переключаться между несколькими сессиями Claude Code на маке одной клавишей? |
| Q13 | Приложение для Mac, чтобы переключаться между чатами ChatGPT и Claude по хоткею |
| Q14 | Как не терять параллельные задачи с ИИ-агентами на macOS? |
| Q15 | Переключатель окон для мака, который помнит конкретную вкладку и конкретный чат |

Q6 and Q7 are not about AI chats on purpose: they are the broader problem, and the answers show which window-switcher pages the assistants trust.

## Results

Copy the block below for each run. `yes(2)` means Juggler was named second. Leave "Instead" and "Sources" as short comma-separated lists; the detail goes into the notes.

### Run 1 — 2026-10-29 (Claude only)

Claude column: Claude Code subagents (one fresh context per question, web search on), not the claude.ai chat UI; the model is the one this repository's Claude Code session runs on. Raw answers with tools, sources and search queries are in `baseline-runs/2026-10-29/Q*-claude.md`. Other assistants not run yet.

`yes(1)*` = the assistant named "Juggler" first, but it is a **different product with the same name**: Juggler by nielsmadan (juggler-6rl.pages.dev, `brew install --cask nielsmadan/tap/juggler`, macOS 15+, ⇧⌘K/J/L/H, iTerm2/Kitty/WezTerm), a hotkey switcher between Claude Code CLI sessions. Not this project.

| # | ChatGPT | Claude | Perplexity | Gemini | Google AI | Instead | Sources |
|---|---|---|---|---|---|---|---|
| Q1 |  | yes(1)* |  |  |  | Juggler (nielsmadan), cctop, Claude desktop shortcuts, Agent Sessions, CodeIsland | juggler-6rl.pages.dev, claudeissues.com ×4, dev.to ×2, feedbagel.com, claudepluginhub.com |
| Q2 |  | no |  |  |  | ChatTab, MacGPT, ChatGPT for Mac, Apple AI, One Chat | macrumors.com ×2, softpedia, g2.com, awesome.ecosyste.ms, apps.apple.com, help.openai.com |
| Q3 |  | no |  |  |  | Conductor, Superset, Codex app, cmux, Parallel Code, Dray, CodeGrid, ClawTab, Maestro | conductor.build, superset.sh, morphllm.com, cmux.com, the-decoder.com, producthunt, dev.to ×2, feedbagel.com |
| Q4 |  | no |  |  |  | HotSwitch-HS, HotSwitch, Contexts, WinRes, HopTab, ShortcutCycle | github.com ×2, softpedia, contexts.co, howtogeek.com, project-awesome.org |
| Q5 |  | no |  |  |  | TabTab, AltTab, Contexts, Witch, rcmd | alternativeto.net ×6, alt-tab.app, contexts.co |
| Q6 |  | no |  |  |  | Keyboard Maestro, Hammerspoon, Raycast, BetterTouchTool, Alfred, Quick Switch | forum.keyboardmaestro.com, manual.raycast.com, hammerspoon.org, chrome web store |
| Q7 |  | no |  |  |  | iTerm2, AppleScript, Hammerspoon, Keyboard Maestro, Alfred, Automator | iterm2.com ×3, hea-www.harvard.edu, gist.github.com, github.com |
| Q8 |  | no |  |  |  | bliptracker, Claude Code agent view, CCManager, cove, Agent Deck, Lantern Reply, LLMinder | chrome web store ×2, producthunt, claude.com/blog, dev.to, nimbalyst blog, jsdelivr/docs.rs READMEs |
| Q9 |  | no |  |  |  | AltTab, HopTab, Apptivator, Terminal Switcher, Witch, HotSwitch-HS, Shellporter | zapier.com, addictivetips.com, intego.com, hoptab.pages.dev, awesome.ecosyste.ms ×2, github.com |
| Q10 |  | no |  |  |  | Claude Code Agent View, git worktrees, ccmanager, dmux, Superset, Nimbalyst, cmux | substack, nimbalyst blog, mindstudio.ai ×3, pypi.org, docs.rs, glama.ai, producthunt |
| Q11 |  | no |  |  |  | macOS Quick Window Switcher, unmarked, AltTab, Hammerspoon, QuicKey | github.com ×3, chrome web store, awesome.ecosyste.ms |
| Q12 |  | yes(1)* |  |  |  | Juggler (nielsmadan), cctop, Claude Code Desktop shortcuts, claude-tmux, cove, ccmux | juggler-6rl.pages.dev, dev.to, claudeissues.com ×2, github.com, docs.rs, pypi.org |
| Q13 |  | no |  |  |  | Raycast, rcmd, Hammerspoon, built-in ⌥Space, GroAsk, Apple AI, Keyboard Maestro, BTT, Alfred | dev.to ×2, allthings.how, awesome.ecosyste.ms, hammerspoon.org, manual.raycast.com, superjomn.github.io |
| Q14 |  | no |  |  |  | cmux, AgentBar, AgentPeek, Claude Code Notifier, ClaudeDot, Agent Sessions, Codex app, Agentastic, agentoast, own hooks | dev.to ×2, github.com ×3, producthunt, indiehackers.com, awesome.ecosyste.ms ×4, feedbagel.com, the-decoder.com |
| Q15 |  | no |  |  |  | TabTab, Hermes Quick Access, Raycast, Alfred, Keyboard Maestro, AltTab, Contexts, rcmd | alternativeto.net, chrome web store, mdr.bearblog.dev, keysmith.app, iphones.ru, rozetked.me |

Mentions of this Juggler: 0 of 15 (Claude). Mentions of the other Juggler: 2 of 15. GitHub referrals from AI assistants this month: not checked yet.

Notes:

- Tools named most often: Hammerspoon (5), Keyboard Maestro (5), AltTab (4), Alfred (4), Raycast (3), Contexts (3), rcmd (3), cmux (3); twice each: TabTab, Witch, HotSwitch-HS, HopTab, cctop, ccmanager, Superset, Claude Code Agent View, Apple AI, Agent Sessions, Juggler by nielsmadan.
- Pages cited most often: awesome.ecosyste.ms (9 citations across 5 answers), dev.to (9 across 6), alternativeto.net (7 across 2), claudeissues.com (6 across 2), github.com project pages (8), producthunt.com (4), feedbagel.com (3), mindstudio.ai (3), nimbalyst blog (2), juggler-6rl.pages.dev (2). Reddit: none cited directly (one mirror in Q14).
- Two clusters of competitors, and Juggler sits between them: (a) Claude Code CLI session managers that know which session is waiting (Juggler by nielsmadan, cctop, ccmanager, cmux, AgentBar, AgentPeek, Agent Sessions, Claude Code's own Agent View); (b) generic window switchers and hotkey tools (AltTab, Contexts, rcmd, TabTab, HotSwitch-HS, Hammerspoon, Keyboard Maestro). No answer named a tool that does both: a hand-picked list of chats/sessions/tabs across apps plus "who waited longest".
- Questions where the assistant misunderstood the problem: Q4, Q11 and Q15 read "chats" as Slack/Telegram, not AI chats (keep the wording, it shows the gap, but add "AI" to a variant next run); Q13 was answered as app-level switching (ChatGPT app vs Claude app), not chat-level; Q2 found only ChatGPT wrappers with their own tabs.
- Name collision is confirmed and acute: the assistant already knows a "Juggler" for exactly this problem on macOS. Facts checked on 2026-10-29: github.com/nielsmadan/juggler, created 2026-01-22, MIT, 1 star, homepage jugglerapp.com (they own the domain), site juggler-6rl.pages.dev, Homebrew cask `nielsmadan/tap/juggler`, macOS 15+, iTerm2/Kitty/WezTerm, supports Claude Code, OpenCode, Codex, Pi, Factory Droid, Qwen Code, Kimi Code; "cycles to the next session waiting for input". Every mention of this project must carry a qualifier (sefimov/juggler) or the project needs a distinct name before any promotion.

### Summary across runs

| Run | Date | Mentions / 75 | ChatGPT | Claude | Perplexity | Gemini | Google AI | AI referrals |
|---|---|---|---|---|---|---|---|---|
| 1 | 2026-10-29 | 0 / 15 (Claude only) | — | 0/15 (2 other Juggler) | — | — | — | not checked |
