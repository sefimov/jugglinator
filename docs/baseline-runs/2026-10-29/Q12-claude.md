# Q12 — Claude (Claude Code subagent with web search), 2026-10-29

**Question:** Как переключаться между несколькими сессиями Claude Code на маке одной клавишей?

**Juggler mentioned:** yes(1), but a DIFFERENT product with the same name: "Juggler" by nielsmadan (juggler-6rl.pages.dev, brew cask nielsmadan/tap/juggler, macOS 15+). Not sefimov/juggler.

## Answer

Короткий ответ: встроенной «одной клавиши» для переключения между несколькими CLI-сессиями Claude Code в терминале нет — это зависит от того, где они запущены. Вот что можно использовать, в порядке моих рекомендаций:

1. **Juggler** (бесплатное open-source menu-bar приложение для macOS 15+). Самое близкое к тому, что вы описали: глобальный хоткей ⇧⌘K перекидывает вас на следующую сессию, которая ждёт ввода (⇧⌘J — предыдущая, ⇧⌘L — отложить текущую), работает поверх iTerm2/Kitty/WezTerm, понимает tmux и SSH, подсвечивает нужную вкладку/панель и шлёт уведомления, когда сессия освободилась или просит разрешение. Ставится через `brew install --cask nielsmadan/tap/juggler` или .dmg с GitHub; хоткеи настраиваемые.

2. **cctop** — menu-bar приложение: по хоткею поверх всех сессий появляются цифры 1–9, нажимаете нужную — и вы в этой сессии. Удобно, если хотите прыгать не «к следующей», а к конкретной.

3. **Claude Code Desktop (официальное приложение)** — если вы запускаете сессии не в терминале, а в десктопном приложении, там есть встроенные Ctrl+Tab / Ctrl+Shift+Tab (или ⇧⌘] / ⇧⌘[) для переключения на следующую/предыдущую сессию. Переход к сессии по номеру (⌘1…9) пока не реализован и кастомизации клавиш нет; на некоторых версиях «предыдущая сессия» глючила.

4. **tmux + claude-tmux** — если сессии живут в tmux: штатные Ctrl-b n / Ctrl-b p / Ctrl-b <номер окна> переключают окна, а claude-tmux добавляет TUI со списком всех инстансов Claude Code и их статусами, вызываемый одним биндом (в README пример — Ctrl-b Ctrl-c). Альтернативы в той же нише: **cove** (одно окно tmux на сессию, навигация стрелками в сайдбаре) и **ccmux**.

5. **Штатные вкладки терминала** — самый простой вариант без дополнительных программ: по сессии на вкладку iTerm2/Terminal.app и ⌘1…⌘9 или ⌘⇧]/⌘⇧[ для переключения. Минус — терминал не знает, какая сессия сейчас ждёт вашего ответа, за это как раз отвечают Juggler и cctop.

Если у вас обычный терминал и вопрос именно «прыгнуть туда, где Claude ждёт меня», я бы начал с Juggler; если нужен произвольный выбор сессии по цифре — cctop.

## REPORT

TOOLS:
Juggler (nielsmadan, not sefimov)
cctop
Claude Code Desktop (встроенные Ctrl+Tab / ⇧⌘])
tmux + claude-tmux (также cove, ccmux)
Вкладки терминала (iTerm2 / Terminal.app, ⌘1…⌘9)

SOURCES:
https://juggler-6rl.pages.dev/
https://dev.to/ozan_kak_75bcbab7a8a1/macos-app-to-monitor-all-running-claude-code-sessions-at-once-1jm8
https://claudeissues.com/issue/61126-feature-desktop-app-jump-directly-to-a-session-tab-by-index-cmd-1-9
https://claudeissues.com/issue/68113-bug-desktop-app-macos-previous-session-shortcuts-ctrl-shift-tab-cmd-shift-do-not
https://github.com/nielsgroen/claude-tmux
https://docs.rs/crate/cove-cli/0.5.2/source/README.md
https://pypi.org/project/ccmux/

SEARCHES:
switch between multiple Claude Code sessions mac hotkey
Claude Code multiple sessions terminal tabs tmux switch shortcut macOS
