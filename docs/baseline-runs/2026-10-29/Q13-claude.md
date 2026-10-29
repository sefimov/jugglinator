# Q13 — Claude (Claude Code subagent with web search), 2026-10-29

**Question:** Приложение для Mac, чтобы переключаться между чатами ChatGPT и Claude по хоткею

**Juggler mentioned:** no

## Answer

Готового приложения «именно для ChatGPT + Claude» не нужно — задача решается любым переключателем окон с хоткеями на конкретное приложение. Что бы я поставил, по порядку:

1. **Raycast** (бесплатно). В настройках Raycast → Extensions → Applications у каждого приложения можно задать свой глобальный хоткей: например, ⌥1 — фокус на окно ChatGPT, ⌥2 — на Claude. Повторное нажатие просто переводит фокус, не открывая новое окно. Самый простой и «не ломающийся» вариант.

2. **rcmd** (App Store, платное, разово). Переключатель приложений по букве: зажимаете правый ⌘ и жмёте C — Claude, G — ChatGPT (буквы можно назначить вручную). Ещё и прячет приложение при повторном нажатии. Если нужны только переключения между 2–3 приложениями, это самое быстрое по ощущениям решение.

3. **Hammerspoon** (бесплатно, open source) — для тех, кто не против написать 5 строк Lua. Со спунами WindowStrider или AppWindowSwitcher хоткей привязывается к bundle ID приложения и при повторных нажатиях циклит окна этого приложения — пригодится, если у вас открыто несколько окон Claude. Требует разрешения Accessibility.

4. **Встроенные хоткеи самих приложений.** У Claude для Mac есть глобальный ⌥Space для быстрого чата из любого места; у ChatGPT в Settings → App можно записать свой хоткей для companion-окна. Учтите: по умолчанию оба претендуют на ⌥Space, так что одному из них назначьте другую комбинацию. Этого может хватить без сторонних утилит.

5. **GroAsk / Apple AI** — если вам нужно не переключаться между двумя окнами, а вызывать все AI из одного окна по одному хоткею (⌥Space, Tab — смена модели). Это маленькие сторонние проекты, GroAsk работает через скриптинг браузера и может ломаться при обновлениях сайтов — ставьте с осторожностью.

Альтернативы из той же серии, если что-то из этого уже стоит: **Keyboard Maestro** или **BetterTouchTool** (макрос «активировать приложение» на хоткей), либо **Alfred** в связке с Hammerspoon для прыжка в окно по его заголовку.

## REPORT

TOOLS:
Raycast
rcmd
Hammerspoon
Claude for Mac (встроенный хоткей)
ChatGPT for Mac (встроенный хоткей)
GroAsk
Apple AI
Keyboard Maestro
BetterTouchTool
Alfred

SOURCES:
https://dev.to/thinkerjack/i-was-switching-browser-tabs-50-times-a-day-to-talk-to-ai-heres-how-i-fixed-it-efp
https://allthings.how/claude-is-now-available-as-a-desktop-app-on-windows-and-mac/
https://blog.kowatek.com/?p=89692
https://awesome.ecosyste.ms/projects/github.com%2Fbunnysayzz%2Fappleai
https://www.hammerspoon.org/Spoons/AppWindowSwitcher.html
https://gh.r-mj.com/Dubzer/WindowStrider.spoon
https://manual.raycast.com/v1/hotkey
https://dev.to/rstacruz/switching-apps-slow-down-my-productivity-and-how-i-fixed-it-2anb
https://superjomn.github.io/posts/alfred-and-hammerspoon-to-jump-window

SEARCHES:
mac app hotkey switch between ChatGPT and Claude windows
macOS global hotkey ChatGPT Claude desktop app quick access menu bar
macOS assign hotkey to switch to specific app window rcmd Raycast Hammerspoon
