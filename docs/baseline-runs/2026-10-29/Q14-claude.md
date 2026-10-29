# Q14 — Claude (Claude Code subagent with web search), 2026-10-29

**Question:** Как не терять параллельные задачи с ИИ-агентами на macOS?

**Juggler mentioned:** no

## Answer

Короткий ответ: завести одно место, которое показывает все запущенные агентские сессии и их состояние («работает / ждёт ответа / просит разрешение / закончил»), и получать уведомление ровно в момент, когда агенту нужен ты. На macOS для этого уже есть готовые инструменты — ниже в порядке, в котором я бы их пробовал.

1. **cmux** — нативный терминал для macOS на базе Ghostty, сделанный именно под параллельных агентов: у каждого воркспейса свой статус в боковой панели, панель, которая ждёт ввода, подсвечивается «кольцом», и нет проблемы одинаковых вкладок. Самый цельный вариант, если вы готовы сменить терминал.

2. **AgentBar** — бесплатное меню-бар приложение, которое через хуки Claude Code ловит момент, когда агент задал вопрос, просит разрешение или простаивает, шлёт уведомление и выводит нужный терминал вперёд. Ничего не блокирует, работает с обычным `claude`.

3. **AgentPeek** — живёт в «чёлке» MacBook и отслеживает сессии Claude Code и Codex из одного места: сессии, которым нужно внимание, всплывают наверх, панель может раскрываться сама. Ставит хуки в `~/.claude/settings.json` и `~/.codex/hooks.json`, работает с любым терминалом (Ghostty, tmux, iTerm).

4. **Claude Code Notifier** — ведёт каждую сессию отдельно, а в иконке меню-бара показывает счётчик сессий, ожидающих ввода; хуки ставятся автоматически. Хороший минимальный вариант, если нужен только «кто меня ждёт».

5. **ClaudeDot / Hive Light** — «светофор» в меню-баре: цвет точки отражает самое срочное состояние среди всех сессий (красный = кто-то ждёт ответа или подтверждения), в панели список сессий. Поддерживают Ghostty, iTerm2, Warp, Terminal.app.

6. **Agent Sessions** — open-source (Rust/Tauri) дашборд для Claude Code и OpenCode с определением состояния в реальном времени (Thinking / Processing / Waiting / Idle); пока только macOS с iTerm2 и Terminal.

7. **Codex app (OpenAI)** — если вы в основном на Codex: официальное macOS-приложение для запуска и контроля нескольких агентов параллельно, интегрировано с CLI, IDE-расширением и облаком. Только для платных планов ChatGPT.

8. **Agentastic.dev / Claudete / Clave / mcode** — «командные центры», где все агенты (Claude Code, Codex, Gemini CLI и т.д.) живут в одном окне, часто с отдельным git worktree на агента и kanban по статусам. Это уже смена рабочего процесса, а не просто уведомления.

9. **agentoast** — если вы живёте в tmux: тост при завершении или ожидании агента, клик переводит в нужную панель.

10. **Свои хуки без сторонних приложений** — Claude Code имеет события `Stop` и `Notification` (у Codex аналогичные хуки); достаточно повесить на них скрипт с `osascript -e 'display notification …'` или `terminal-notifier`, и вы получите системное уведомление при каждом ожидании ввода. Синтаксис хуков сверьте с официальной документацией.

Практический совет: что бы вы ни выбрали, давайте каждой сессии отдельный git worktree и понятное имя вкладки — большинство потерь задач происходит не от отсутствия уведомлений, а от того, что пять одинаковых окон `claude` неотличимы друг от друга.

## REPORT

TOOLS:
cmux
AgentBar
AgentPeek
Claude Code Notifier
ClaudeDot
Hive Light
Agent Sessions
Codex app (OpenAI)
Agentastic.dev
Claudete
Clave
mcode
agentoast
Собственные хуки Claude Code/Codex (osascript / terminal-notifier)

SOURCES:
https://dev.to/arshtechpro/cmux-the-native-macos-terminal-built-for-running-ai-coding-agents-in-parallel-52il
https://github.com/jreed91/agentbar
https://agentpeek-web.pages.dev/sessions/
https://www.producthunt.com/posts/agentpeek
https://dev.to/ccnotifier/how-i-stopped-losing-time-to-stalled-claude-code-sessions-28ji
https://www.indiehackers.com/post/i-built-a-free-mac-app-that-tells-you-when-claude-code-needs-you-so-you-can-stop-watching-your-terminal-Nem4tXVTIa7HyAV3jgDh
https://github.com/poorfish/ClaudeDot
https://vn.linkedin.com/in/fr1j0
https://awesome.ecosyste.ms/projects/github.com%2Fozankasikci%2Fagent-sessions
https://the-decoder.com/openai-launches-codex-app-for-macos-to-manage-multiple-ai-agents/
https://feedbagel.com/post/agentasticdev-native-macos-app-for-running-multiple-ai-coding-agents-in-parallel
https://www.everydev.ai/tools/claudete/llms.txt
https://awesome.ecosyste.ms/projects/github.com%2Fcodika-io%2Fclave
https://awesome.ecosyste.ms/projects/github.com%2Froman10%2Fmcode
https://awesome.ecosyste.ms/projects/github.com%2Fshuntaka9576%2Fagentoast
https://chatgate.ai/post/agentmanager
https://github.com/Hamma111/nudgy
https://reddit.sentinel-team.org/posts/1ujnf5b/snapshots/2026-07-03T03%3A00%3A16.73148Z

SEARCHES:
manage multiple parallel AI coding agents macOS app track sessions Claude Code Codex
macOS menu bar app notifications when Claude Code agent finishes waiting for input parallel sessions
как следить за несколькими параллельными сессиями Claude Code Codex на Mac уведомления когда агент ждёт
