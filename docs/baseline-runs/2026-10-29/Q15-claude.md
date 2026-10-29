# Q15 — Claude (Claude Code subagent with web search), 2026-10-29

**Question:** Переключатель окон для мака, который помнит конкретную вкладку и конкретный чат

**Juggler mentioned:** no

## Answer

Готового переключателя, который по одной горячей клавише возвращает именно «эту вкладку в браузере» и «этот чат в мессенджере», в открытых источниках я не нашёл. Ближе всего такие варианты (в порядке, в котором я бы их пробовал):

1. **TabTab** — нативный переключатель окон и вкладок для macOS: кроме окон умеет переходить к отдельным вкладкам в Chrome, Safari, VS Code, Finder, с поиском по названию вкладки и настраиваемыми хоткеями. Telegram/Slack в списке поддерживаемых не заявлены; бесплатная версия ограничена, полная — $24 разово.
2. **Hermes – Quick Access** (приложение для Mac + расширение Chrome) — вешает горячие клавиши на «важные» вкладки Chrome, чтобы прыгать к ним из любого места. Закрывает браузерную половину задачи, про чаты ничего не умеет.
3. **Raycast или Alfred** — лаунчеры с поиском открытых вкладок браузера; для чатов можно сделать свой workflow/скрипт, который открывает deep-link вида `tg://resolve?domain=…` или `slack://channel?…` и фокусирует приложение. Это самодельный вариант, но единственный, который реально «помнит» и вкладку, и чат.
4. **Keyboard Maestro (или Quicksilver/Shortcuts + AppleScript)** — макрос на хоткей: активировать браузер → через AppleScript выбрать вкладку по URL, активировать Telegram/Slack → отправить ⌘K и имя чата. Работает, но хрупко и требует настройки руками.
5. **AltTab / Contexts / rcmd** — обычные переключатели окон и приложений (по картинкам, по списку, по первой букве). Вкладку или чат они не запоминают, но если задача на самом деле «быстро вернуться в нужное окно», их хватает.

Отдельно: Telegram для macOS и Slack сами помнят последний открытый чат, а браузер — активную вкладку, так что простой ⌘Tab часто уже возвращает «туда, где вы были». Проблема возникает, когда в одном приложении несколько нужных вкладок/чатов — тогда без п. 1–4 не обойтись.

## REPORT

TOOLS:
TabTab
Hermes – Quick Access
Raycast
Alfred
Keyboard Maestro
Quicksilver
AltTab
Contexts
rcmd

SOURCES:
https://alternativeto.net/software/tabtab/about
https://chrome.google.com/webstore/detail/hermes-quick-access-chrom/henjhookbfcopdpjlimchjopggoomcop/reviews
https://mdr.bearblog.dev/dont-cmd-tab-use-alfred-workflows-instead
https://www.keysmith.app/blog/8-essential-keyboard-shortcuts-for-slack-in-2020
https://www.iphones.ru/iNotes/kak-vypolnyat-rabotu-na-mac-bystree-eti-10-prilozheniy-pomogli-mne--05-27-2022
https://rozetked.me/news/9601-v-telegram-dlya-macos-poyavilis-polnocennye-vkladki-s-chatami

SEARCHES:
переключатель окон mac запоминает вкладку браузера и чат Telegram
macOS window switcher switch to specific browser tab and specific Slack channel hotkey
mac app hotkey jump to specific Chrome tab or Telegram chat window switcher remembers tab
