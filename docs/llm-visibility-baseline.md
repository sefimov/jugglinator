# LLM visibility baseline

> The project was renamed from Juggler to **Jugglinator** on 2026-10-29, after run 1 showed the name clash below. From run 2 on, count mentions of Jugglinator; mentions of "Juggler" are the other product.

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

### Run 2 (partial) — 2026-10-30, Claude only, the day after the rename

Five questions re-run the same way (`baseline-runs/2026-10-30/`), to see whether anything changed right after the rename and the v0.3.0 release. A web search for "Jugglinator" returned nothing that day: the new repository and site were not indexed yet.

| # | Claude | Instead | Sources |
|---|---|---|---|
| Q1 | no (Juggler by nielsmadan 1st again) | Juggler (nielsmadan), cctop, claudebar, Clave, TermHub | juggler-6rl.pages.dev, claudeissues.com, cctop.app, github.com ×3 |
| Q2 | no | ChatTab, MacGPT, Apple AI, ChatGPT for Mac | macrumors, toolbit.ai, macgpt.com, macworld, awesome.ecosyste.ms, help.openai.com |
| Q4 (with "AI chats") | no | rcmd, HopTab, Cycler, Apple AI, GroAsk, Hammerspoon | macpowerusers forum, alternativeto.net ×2, github.com ×2 |
| Q9 | no | Context Switch, AltTab, Tab, Witch, Contexts, Apple AI | apps.apple.com, github.com ×2, contexts.co, intego.com |
| Q13 | no | Quiper, GroAsk, AppleAI, IntelliBar, FetchAI, Peek AI | github.com, theaireport.ai, chatgate.ai, theresanaiforthat.com |

Mentions of Jugglinator: 0 of 5. Expected: assistants with search can only cite what is indexed, and nothing about Jugglinator was. Re-check in two to four weeks, after the awesome-list and AlternativeTo submissions.

### Run 3 — 2026-11-14 (Claude only), two weeks after the rename

All 15 questions, verbatim, the same way as run 1: one Claude Code subagent per question, fresh context, web search on, no hint about the project. Raw tool lists, sources and search queries are in `baseline-runs/2026-11-14/Q*-claude.md`. Other assistants not run.

| # | Claude | Instead | Sources |
|---|---|---|---|
| Q1 | no (Juggler by nielsmadan 4th, first third-party tool) | Claude desktop shortcuts, iTerm2, tmux, Juggler (nielsmadan), cctop, Hawky, Raycast Agent Inbox, AgentManager, Clave | claudeissues.com ×3, juggler-6rl.pages.dev ×2, cctop.app ×2, alternativeto.net, raycast.com, producthunt, awesome.ecosyste.ms, dev.to |
| Q2 | no | Quiper, Kikumap, MacGPT, Apple AI, GroAsk, Peek, PromptBar, ChatGPT desktop app | producthunt ×2, awesome.ecosyste.ms ×2, dev.to, help.openai.com, elephas.app, macworld, indiehackers |
| Q3 | no | git worktrees, Conductor, Codex app, Agent of Empires, Claude Squad, cmux, Agentastic, Parallel Code, CodeGrid, Vibe Island, Agent Sessions | betterstack.com ×2, conductor.build ×2, feedbagel.com ×2, hunted.space ×2, awesome.ecosyste.ms ×2, vibeisland.app ×2, morphllm.com, the-decoder.com |
| Q4 | no | HopTab, Quick Tab, rcmd, ShortcutCycle, AltTab, Witch, Contexts, Hammerspoon, Keyboard Maestro, BetterTouchTool | alternativeto.net ×2, alt-tab.app ×2, apps.apple.com, cultofmac, digitaltrends, zapier, project-awesome.org |
| Q5 | no | AltTab, BetterCmdTab, Better Window Switcher, WindowHopper, OneSwitch, Witch, Switch, Peek, Raycast, Alfred | alt-tab.app ×3, opensourcealternatives.to ×3, alternativeto.net ×2, setapp.com ×2, softpedia ×2, producthunt |
| Q6 | no | Tab Hot Key, Hermes Quick Access, AppleScript, Keyboard Maestro, Hammerspoon, Raycast, BetterTouchTool, Alfred, TabGroup Trigger | chrome web store ×4, support.google.com, github.com, workona.com |
| Q7 | no (Juggler by nielsmadan last, 11th; new here) | AppleScript, Hammerspoon, Automator, Shortcuts, Keyboard Maestro, BetterTouchTool, Alfred, Raycast, iTerm2, Juggler (nielsmadan) | discussions.apple.com ×2, docs.rs ×2, scriptingosx.com, juggler-6rl.pages.dev, mdr.bearblog.dev |
| Q8 | no | bliptracker, Chat Timeline, AgentPet, Harbar, lazyagent, Agent Signals, Agent Inbox | chrome web store ×2, producthunt ×2, awesome.ecosyste.ms, claudepluginhub.com, raycast.com |
| Q9 | no | AltTab, Raycast, Witch, Terminal Switcher, Nudge, TermBar, Agent Control Tower Lite, Apple AI, GroAsk, Menu AI | awesome.ecosyste.ms ×2, dev.to ×2, producthunt ×2, github.com ×2, apps.apple.com, alt-tab.app |
| Q10 | no | git worktrees, Claude Code agent view, Claude Code Desktop, tmux, Claude Squad, amux, Conductor, Vibe Kanban, Nimbalyst | claude.com/blog, amux.io ×2, nimbalyst ×2, buildfastwithai.com, blog.gitbutler.com, dev.to |
| Q11 | no | BetterCmdTab, foxhop, OneSwitch, Winby, AltTab, Reef, Hammerspoon | github.com ×6, opensourcealternatives.to ×2, raycast.com, alternativeto.net |
| Q12 | no (Juggler by nielsmadan 4th, first third-party tool) | Claude Desktop shortcuts, Terminal, iTerm2, Juggler (nielsmadan), cctop, cmux, AgentManager, Raycast Agent Inbox | code.claude.com ×3, claudeissues.com ×2, juggler-6rl.pages.dev ×2, cctop.app ×2, cmux.com, producthunt |
| Q13 | no | GroAsk, Apple AI, Quiper, Adro Browser, BoltAI, MindMac, Beam, Raycast, Alfred, Hammerspoon | dev.to ×2, hashnode ×2, thedailyworkflow.com ×2, awesome.ecosyste.ms, apps.apple.com, help.openai.com |
| Q14 | no | git worktree, Codex app, cmux, Supacode, Crew Tower, Agent Sessions, AgentsRoom, Verdent Deck, Axel, AgentMicro, Agent of Empires | aipure.ai ×2, huntscreens.com ×2, comss.ru, cmux.com, betterstack.com, awesome.ecosyste.ms |
| Q15 | no | ReturnFast, TabTab, Better Window Switcher, Hermes Quick Access, ReTab, JumpTab, AltTab, BetterTouchTool, Keyboard Maestro | producthunt ×3, apps.apple.com ×3, alternativeto.net ×2, chrome web store ×2, alt-tab.app |

Mentions of Jugglinator: 0 of 15 (Claude). Mentions of the other Juggler: 3 of 15 (Q1, Q7, Q12; run 1 had Q1 and Q12). GitHub traffic for the last 14 days: 6 views, 1 unique visitor, the only referrer is github.com; no referrals from AI assistants.

Notes:

- Jugglinator is still not in the search index. Two direct web searches on 2026-11-14 ("Jugglinator" and "Jugglinator macOS menu bar app AI chats") returned nothing about the project: the first returned juggling robots, the second other menu bar AI apps. Until the name is findable, no assistant with search can cite it, whatever the question.
- Seven answers say outright that no tool for the job was found (Q2, Q4, Q8, Q9, Q11, Q13, Q15): a list of specific chats across apps, a hotkey to the next one, "who waited longest". This is the gap Jugglinator fills, and the assistant has nothing to put there.
- Tools named most often: AltTab (5), Hammerspoon (5), Raycast (5), Keyboard Maestro (4), BetterTouchTool (4), Alfred (4), Witch (3), cmux (3), Apple AI (3), GroAsk (3), Juggler by nielsmadan (3). New since run 1: BetterCmdTab, Better Window Switcher, OneSwitch, Quiper, Kikumap, Agent of Empires, Raycast Agent Inbox.
- Pages cited most often: awesome.ecosyste.ms (7 answers), producthunt.com (7), github.com project pages, dev.to (5), alternativeto.net (5), apps.apple.com (5), chrome web store (3). These are the same catalogs as in run 1, so the submission list stands: awesome lists, AlternativeTo, Product Hunt.
- Caveat on this run: the 15 subagents searched at the same time and hit the search rate limit. Nine of the 15 answers lost at least one search (`too_many_requests`); in two more a retry succeeded. Every answer still had at least two successful searches, but the tool lists are thinner than they would be with all searches, and parts of some answers came from general knowledge (noted per file). Next run: start the questions in batches of four or five.
- Q4, Q11 and Q15 were again read as Slack/Telegram chats, not AI chats.

### Summary across runs

| Run | Date | Mentions / 75 | ChatGPT | Claude | Perplexity | Gemini | Google AI | AI referrals |
|---|---|---|---|---|---|---|---|---|
| 1 | 2026-10-29 | 0 / 15 (Claude only) | — | 0/15 (2 other Juggler) | — | — | — | not checked |
| 2 (partial) | 2026-10-30 | 0 / 5 (Claude only) | — | 0/5 (1 other Juggler) | — | — | — | 0 (21 views, all own) |
| 3 | 2026-11-14 | 0 / 15 (Claude only) | — | 0/15 (3 other Juggler) | — | — | — | 0 (6 views, 1 visitor) |
