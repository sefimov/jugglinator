# Q5 — Claude (Claude Code subagent with web search), 2026-10-29

**Question:** Alternative to Cmd-Tab that switches between specific tabs and windows, not whole apps

**Juggler mentioned:** no

## Answer

If you want a Cmd-Tab replacement that lands you on a specific window or even a specific browser/editor tab, here is what I would try, in order:

1. **TabTab** (macOS, free tier + ~$24 one-time) – the closest match to "tabs, not apps". It replaces Cmd-Tab with a switcher that lists individual windows and the tabs inside apps like Chrome, VS Code and Figma, and version 2.0 added full-text search across open tabs, so you can jump straight to a tab without first bringing the app forward.

2. **AltTab** (free, open source) – a Windows-style Alt-Tab for macOS that shows a thumbnail per window (including minimized/hidden ones, across Spaces and monitors) instead of one icon per app. It does not see inside browser tabs, but if "windows, not apps" is the main pain, this is the free default pick; you can remap it onto Cmd-Tab.

3. **Contexts** ($9.99, free trial; Ventura–Sequoia) – a window switcher where you type a few characters of an app name or window title to filter the list; also offers an improved Cmd-Tab, a sidebar and a scroll gesture. Window-level only, no tab support, but the search-by-title workflow is very fast once you get used to it.

4. **Witch** (paid) – a long-standing window switcher that pops up a list of window titles on a shortcut; good if you prefer a text list over thumbnails. Window-level only.

5. **rcmd** (paid) – reimagined Cmd-Tab where you hold the right Command key and press the first letter of the app; useful for direct jumps but less about windows/tabs, so lower priority for your question.

Built-in fallback: Cmd-` cycles windows of the frontmost app only, and in Chrome/Safari Cmd-1…9 and Cmd-Shift-A (Chrome tab search) jump to tabs inside the current browser, which partially covers the tab side without any extra app.

## REPORT

TOOLS:
TabTab
AltTab
Contexts
Witch
rcmd

SOURCES:
https://alt-tab.app/cmd-tab-doesnt-switch-windows
https://contexts.co/
https://alternativeto.net/software/tabtab/
https://alternativeto.net/news/2025/8/tabtab-2-0-launches-with-faster-performance-and-full-tab-search-on-mac
https://alternativeto.net/software/contexts/
https://alternativeto.net/software/witch
https://alternativeto.net/software/rcmd/
https://alternativeto.net/software/alttab

SEARCHES:
mac app switch between specific windows and tabs instead of apps alternative to Cmd-Tab
macOS window switcher browser tabs Alt-Tab Contexts rcmd Witch 2026
TabTab mac switch windows and tabs Chrome VSCode Figma search
