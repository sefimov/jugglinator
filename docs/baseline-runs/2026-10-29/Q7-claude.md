# Q7 — Claude (Claude Code subagent with web search), 2026-10-29

**Question:** How to switch to a specific Terminal tab with a global hotkey on Mac

**Juggler mentioned:** no

## Answer

Short version: Apple's Terminal has no built-in way to bind a global hotkey to one specific tab, so you either script it (AppleScript + a hotkey launcher) or switch to iTerm2, which has per-session hotkeys built in.

1. **iTerm2 (built-in, no scripting).** iTerm2 lets you assign a hotkey to a particular session: in that session's settings (General tab) you can "set a hotkey that opens iTerm2 to reveal that session" — press it from any app and iTerm2 comes forward on that tab. It also has dedicated hotkey windows (a profile-bound window toggled by its own hotkey, pinnable and floating), which is the usual way people get a "my server tab on ⌥1" workflow. Needs Accessibility/assistive access enabled in System Settings.

2. **AppleScript bound to a hotkey (works with Apple's Terminal.app).** Terminal's scripting dictionary exposes `selected tab of window` and `custom title of tab`, so a few lines like `set selected tab of window id w to tab t of window id w`, `set index of window id w to 1`, `set frontmost of window id w to true`, `activate` will jump to a tab you've named (Shell > Edit Title / `printf '\e]1;name\a'`). Wrap it in a script that searches tabs by title (the Harvard terminal-tabs script does exactly this, including a picker when several match), then bind it with one of the launchers below. macOS will ask for Automation permission for Terminal the first time.

3. **Hammerspoon (free) as the hotkey glue.** `hs.hotkey.bind({"ctrl","alt"}, "1", function() hs.osascript.applescript([[...]]) end)` gives you a true system-wide binding without any paid tool; keep one binding per tab name. Note that `hs.tabs` is not what you want — it tabs an app's windows, it does not touch Terminal's own tabs.

4. **Keyboard Maestro or Alfred (paid) as the hotkey glue.** Both can run an AppleScript on a global hotkey; Alfred Powerpack workflows (Hotkey trigger → Run Script) and Keyboard Maestro macros are the common no-code route. Alfred/Keyboard Maestro on their own only switch to the *app*, not a tab, so you still need the script from step 2.

5. **Automator Quick Action + System Settings > Keyboard > Shortcuts > Services.** Zero extra software: save the AppleScript as a Quick Action, then assign it a shortcut under Services. Works but Services shortcuts are flakier than the tools above (they sometimes need the focused app to have a text context).

Practical recommendation: if you're on Terminal.app and want it today, do #2 + #3; if you're open to switching terminals, #1 is the cleanest.

## REPORT

TOOLS:
iTerm2
AppleScript (Terminal.app scripting: selected tab / custom title)
Hammerspoon
Keyboard Maestro
Alfred
Automator Quick Action (Services keyboard shortcut)

SOURCES:
https://iterm2.com/documentation-hotkey.html
https://iterm2.com/documentation-preferences-profiles-keys.html
https://iterm2.com/documentation-general-usage.html
https://hea-www.harvard.edu/~fine/OSX/terminal-tabs.html
https://commandpost.fcp.cafe/api-references/hammerspoon/hs.tabs
https://mdr.bearblog.dev/dont-cmd-tab-use-alfred-workflows-instead
https://community.keyboard.io/t/key-to-switch-to-specific-mac-app/440/3
https://gist.github.com/rbreaves/878f8b75a24addd50f5212566036395b
https://github.com/cuiko/TermIMS

SEARCHES:
macOS global hotkey switch to specific Terminal tab
iTerm2 hotkey window dedicated hotkey profile jump to tab global shortcut
AppleScript Terminal.app select tab by title set selected tab hotkey Hammerspoon
