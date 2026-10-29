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

### Run 1 — YYYY-MM-DD

| # | ChatGPT | Claude | Perplexity | Gemini | Google AI | Instead | Sources |
|---|---|---|---|---|---|---|---|
| Q1 |  |  |  |  |  |  |  |
| Q2 |  |  |  |  |  |  |  |
| Q3 |  |  |  |  |  |  |  |
| Q4 |  |  |  |  |  |  |  |
| Q5 |  |  |  |  |  |  |  |
| Q6 |  |  |  |  |  |  |  |
| Q7 |  |  |  |  |  |  |  |
| Q8 |  |  |  |  |  |  |  |
| Q9 |  |  |  |  |  |  |  |
| Q10 |  |  |  |  |  |  |  |
| Q11 |  |  |  |  |  |  |  |
| Q12 |  |  |  |  |  |  |  |
| Q13 |  |  |  |  |  |  |  |
| Q14 |  |  |  |  |  |  |  |
| Q15 |  |  |  |  |  |  |  |

Mentions: 0 of 75. GitHub referrals from AI assistants this month: 0.

Notes:

- Tools named most often:
- Pages cited most often:
- Questions where the assistant misunderstood the problem (rephrase next time, keep the old wording in the notes):

### Summary across runs

| Run | Date | Mentions / 75 | ChatGPT | Claude | Perplexity | Gemini | Google AI | AI referrals |
|---|---|---|---|---|---|---|---|---|
| 1 |  |  |  |  |  |  |  |  |
