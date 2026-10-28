# Juggler

A macOS menu bar app. It keeps a list of parallel chat tasks and cycles through them with a hotkey. On each switch it opens the bound chat in Claude, a Claude Code session, a ChatGPT thread, a Grok Bot window, a Chrome tab, or a Terminal window and tab.

- Bundle id: `com.sefimov.juggler`.
- Requires macOS 14 or later.
- The interface is available in 12 languages: Arabic, Chinese (Simplified), English, French, German, Hindi, Italian, Japanese, Korean, Portuguese (Brazil), Russian, Spanish. The language follows the macOS settings and falls back to English for anything else; you can change it for Juggler alone in Settings → Language. See "Localization" for details.

## Quick start

```sh
scripts/bundle.sh            # build, sign and self-test build/Juggler.app
open build/Juggler.app       # launch: an icon with the task number appears in the menu bar
```

Then:

1. Open a chat in Claude, a session on the Code tab in Claude, a chat in ChatGPT or Grok Bot, a tab in Chrome, a Terminal window.
2. Press ⌃⌥§ or choose "Add Current Window" in the Juggler menu. Tasks are added only from the current window: there is no "New task" field in the menu. Pressing ⌃⌥§ again in a window that is already a task removes it, see "Add or remove the current window".
3. Repeat for the other tasks.
4. Cycle forward with ⌃§, backward with ⌃⇧§.

On the first binding Juggler asks for permissions, see "Permissions". To keep permissions from resetting after every rebuild, sign the app with the "Juggler Dev" certificate, see "Signing".

## Building and checks

Only the Command Line Tools with Swift 6.x are needed; full Xcode is not required.

```sh
swift build                         # build all targets
swift run JugglerChecks             # logic checks: exit code 0 — all passed, 1 — failures
swift run JugglerChecks -v          # print every passed check
swift run JugglerChecks Core Bind   # run only the selected suites
swift run JugglerChecks --self-fail # deliberate failure: make sure the exit code is non-zero

swift run Juggler                   # run the menu bar app (without an .app)
swift run Juggler --self-test       # self-test of components without windows or permission prompts
swift run Juggler --probe-frontmost # JSON with the frontmost window context
```

`swift run Juggler` is handy for debugging. But without an `.app`, macOS grants permissions to Terminal rather than Juggler, and launch at login does not work. For everyday use, build the `.app`.

## Building the .app

```sh
scripts/bundle.sh                                   # ad-hoc signing
JUGGLER_SIGN_IDENTITY="Juggler Dev" scripts/bundle.sh  # sign with your own certificate
scripts/bundle.sh --no-self-test                    # skip the self-test at the end
JUGGLER_VERSION=0.2.0 scripts/bundle.sh             # custom version (default 0.1.0)
```

What the script does:

1. Builds a release: `swift build -c release --product Juggler`.
2. Assembles `build/Juggler.app`. `Info.plist` comes from the `scripts/Info.plist` template:
   - `CFBundleIdentifier` — `com.sefimov.juggler`;
   - `LSUIElement` — no Dock icon, menu bar only;
   - `LSMinimumSystemVersion` — 14.0;
   - `NSAppleEventsUsageDescription` — the explanation shown when asking to control Chrome and Terminal, translated in `InfoPlist.strings`;
   - `CFBundleDevelopmentRegion` — `en`, `CFBundleLocalizations` — the 12 languages from `Localization/*.lproj`, which are copied into `Contents/Resources`;
   - `CFBundleVersion` — the number of commits in `git`.
3. Validates `Info.plist` with `plutil -lint`.
4. Signs with the identity from `JUGGLER_SIGN_IDENTITY`, ad-hoc (`-`) by default.
5. Verifies the signature: `codesign --verify --strict --verbose=2`.
6. Runs `build/Juggler.app/Contents/MacOS/Juggler --self-test`.

Any failure stops the script with a non-zero exit code. The `build/` folder is not committed to `git`.

The self-test can also be run on its own:

```sh
build/Juggler.app/Contents/MacOS/Juggler --self-test; echo $?
```

It initializes the store, the composition root and the UI, SWITCH and BIND modules. It checks the "hotkey → switcher → card" chain, "⌃⌥ → add or remove the current window", removing the frontmost window's task and restoring it with a second ⌃⌥§, Carbon hotkey registration, and the `Info.plist` keys of the built `.app`. It shows no windows and requests no permissions. Exit code 0 means everything passed.

## Running

- `open build/Juggler.app` launches the built app. If Juggler is already running, quit it first: Juggler menu → "Quit".
- **Launch at login** is turned on in Juggler settings (menu → "Settings…"). It works only from the `.app`, and is most reliable when the app lives in `/Applications`:
  ```sh
  ditto build/Juggler.app /Applications/Juggler.app
  ```
  If macOS asks for confirmation, an "Open Login Items" button appears in Juggler settings.
- Data lives in `~/Library/Application Support/Juggler/tasks.json`, custom hotkeys in `hotkeys.json` next to it.

## Hotkeys

| Action | Default | ANSI keyboard |
|---|---|---|
| Next task | ⌃§ | ⌃` |
| Previous task | ⌃⇧§ | ⌃⇧` |
| Add or remove current window | ⌃⌥§ | ⌃⌥` |

- § is the physical key above Tab, to the left of 1. In the Russian layout it types `<`. The hotkey is bound to the key itself, not the character, so it works in both RU and EN layouts.
- Juggler detects the keyboard type (ISO with § or ANSI with `) and picks the defaults accordingly.
- The switching order is fixed: 1→2→3→1. Tasks marked "done" are skipped. The current task is determined at the moment of the key press from the frontmost window or tab.
- On each switch, a card with the number, title, note and "away N min" appears for a second or so. The card does not take focus and lets clicks through.
- **Reassigning:** Juggler settings → "Hotkeys". Click the field, then press the desired combination; Esc cancels, "Default" restores the default.
- `~/Library/Application Support/Juggler/hotkeys.json` stores only reassigned combinations. Defaults are computed at launch from the keyboard type. To reset everything, quit Juggler and delete this file.
- Global (Carbon) hotkeys work only while the app is running. The hotkeys themselves do not need the Accessibility permission.

## Add or remove the current window

⌃⌥§ ("Add or Remove Current Window" in the hotkey settings) and the menu item work as a toggle. The menu item's label depends on the window that was frontmost before the menu opened: not a task — "Add Current Window", already a task — "Remove Current Window". The window is read when the menu opens, without system prompts; if it cannot be read, the item is labeled "Add Current Window".

Below the task list, under a separator, in a column: "Add Current Window" or "Remove Current Window", "Restore Removed Task" (only when there is something to restore), "Settings…", "Quit".

- **The frontmost window is already a task** — the task is removed from the list, and the removal is saved to `tasks.json` right away. A card appears: "Task N “…” removed — ⌃⌥§ within 5 s restores it". It stays visible for the full 5 seconds.
- **Pressing ⌃⌥§ again within those 5 s** puts the task back in its old place — with the same number, note, "done" mark, binding and visit time. It does not matter where focus is at that moment.
- **The "Remove Current Window" menu item** does the same as the hotkey: the same card, the same restore with a second ⌃⌥§ within 5 s. The menu item itself does not restore the task during those 5 s: that is what "Restore Removed Task" is for, and the item's label always matches what it does.
- **After 5 s** ⌃⌥§ is an ordinary toggle again: the window that used to be a task is added again as a new task.
- **The "Restore Removed Task" menu item** appears after a removal and restores the last removed task — whether it was removed with ⌃⌥§ or from the list. Only the last one is remembered, and only until Juggler quits.
- **The frontmost window is not a task** — the existing "Make current chat a task" behavior: the window becomes a new task or is bound to the current task if it has no binding, see "Bindings".

The frontmost window counts as a task only on an exact match. The fallback "last active task" used when cycling is not used here. If nothing matches, nothing is removed.

- Chrome tab — the same tab id or the same URL. Without AppleScript access to Chrome the tab is unknown, so there is no match.
- Claude chat — the same UUID: in Claude desktop or at `claude.ai/chat/<uuid>` in Chrome. The window title alone is not enough.
- Claude Code session — the same `local_<uuid>`.
- ChatGPT thread — the same thread name, i.e. the ChatGPT window title without the " - ChatGPT" suffix, case-insensitive. A window with no thread ("ChatGPT") matches nothing.
- Terminal window — the same tab (tty) or, if either side's tty is unknown, the same window (window id). Another tab of the same window is not a task. The title does not matter: changing the command or window size does not break the match. Only without permission to control Terminal is the window compared by its title, minus the size, shell name and `user@host`.
- App window (Grok Bot and others) — the same bundle id and the same non-empty window title. Without the Accessibility permission the title cannot be read, so there is no match. If a tab, chat or session id was read from the window, a "window only" binding does not apply.

If several tasks match, a match by id wins, then by URL, then by name. On a tie, the last active task wins, otherwise the first in the list.

## Bindings

"Make current chat a task" (⌃⌥§ when the frontmost window is not yet a task) looks at the frontmost window. If the Juggler menu is in front, the last active app is used.

- **Google Chrome** (`com.google.Chrome`) — the active tab: id, URL, title. On switching, Juggler looks for the tab by id, then by URL, and otherwise reopens the URL.
- **Claude** (`com.anthropic.claudefordesktop`) — the chat by UUID. Juggler tries to read the chat URL via Accessibility. If that fails, it asks you to paste the chat URL: `https://claude.ai/chat/<uuid>`, `claude://claude.ai/chat/<uuid>` or a bare UUID. The URL is visible in the address bar if you open the chat on claude.ai in a browser. A "Share" link (`claude.ai/share/…`) will not do: it is a public copy of the conversation, not the chat itself. Juggler recognizes it and says so. The chat is opened with a `claude://claude.ai/chat/<uuid>` link.
- **Claude Code session** (the Code tab in Claude desktop) — the session by id `local_<uuid>`.
  - On the Code tab, ⌃⌥ and "Make current chat a task" bind the session immediately, without a dialog. Juggler reads its URL `https://claude.ai/epitaxy/local_<uuid>` via Accessibility.
  - The task name is the session's `title` from `~/Library/Application Support/Claude/claude-code-sessions/…/local_<uuid>.json`. If there is no file or title, the cleaned window title is used, and if that is empty too (for the Code tab it is just "Claude") — "Claude Code session". Juggler only reads these files.
  - It is opened with a `claude://claude.ai/epitaxy/local_<uuid>` link. The current task is determined by the session id in Claude's frontmost window, so the 1→2→3→1 cycle works between sessions too.
  - In the link dialog the session can also be entered manually: `https://claude.ai/epitaxy/local_<uuid>`, `claude://claude.ai/epitaxy/local_<uuid>` or a bare `local_<uuid>`.
  - In the list such a task has a terminal icon and the "Claude Code" label.
  - Without the Accessibility permission the session id cannot be read, and Juggler shows the link dialog.
- **ChatGPT** (`com.openai.codex`, formerly `com.openai.chat`) — the thread by id, opened with a `codex://threads/<id>` link.
  - Where the id comes from. The ChatGPT window title is the name of the open thread; Juggler reads it via Accessibility. ChatGPT keeps its thread list in `~/.codex/session_index.jsonl` (or `$CODEX_HOME/session_index.jsonl`): one JSON line per change, `{"id": "…", "thread_name": "…", "updated_at": "…"}`. The same id appears several times when a thread is renamed — the name with the latest `updated_at` wins. Juggler looks for a thread whose name matches the window and takes its `id`.
  - Names are compared ignoring extra whitespace; if there is no exact match — case-insensitively and without suffixes like " - ChatGPT".
  - Exactly one thread found — ⌃⌥ and "Make current chat a task" bind it immediately, without a dialog. The task name is the thread name.
  - None found — the usual link dialog: paste `codex://threads/<id>` or bind just the window.
  - Several different threads with that name — the same dialog, but with the link to the most recently updated thread already filled in. If it is the right thread, click "Bind".
  - Juggler only reads the file, and only searches it when binding. A missing file, a file over 16 MB or broken lines are not errors: broken lines are skipped, and at worst you get the link dialog.
  - Without the Accessibility permission the window title cannot be read, so you get the link dialog.
  - When switching, the current ChatGPT task is still determined by the window title (the thread id is not read from the frontmost window). If the thread is renamed, the task is not recognized by its new title.
- **Terminal** (Terminal.app, `com.apple.Terminal`) — window and tab.
  - ⌃⌥§ and "Add Current Window" bind the frontmost Terminal window and its selected tab immediately, without a dialog. Via AppleScript Juggler reads the persistent window id (`id of window`) and the tab's tty (`tty of selected tab`, e.g. `/dev/ttys003`), and keeps the window title as a fallback.
  - The task name is the window title without the size (`214×24`), shell name (`-zsh`, `bash`…), `user@host`, tty and indicator icons: "sergejefimov — sergejefimov@MacBook-Pro-Sergej — -zsh — 214×24" → "sergejefimov". If only noise is left — "Terminal".
  - On switching, Juggler looks for the tab by tty, then the window by id, then the window by its de-noised title, selects the tab and brings the window to the front. If the tab was closed, its window is brought forward and the card says so; if the window is closed, Terminal is brought forward with the message "Terminal window closed — Terminal was brought forward." The window id and tty live until the window is closed or Terminal restarts; after a restart, only the title search remains.
  - The current task when cycling and on ⌃⌥§ recognizes a Terminal window by tty or window id, not by title, so changing the command or window size breaks nothing.
  - Permission to control Terminal is required, see "Permissions". Without it, a Terminal window is bound as an ordinary window, by title (also compared without size and shell), and switching raises a window with that title without selecting a tab.
  - In the list such a task has a Terminal icon and the "Terminal" label. Tasks bound to Terminal as an ordinary window before this version stay as they were; to get a tab binding, remove such a task and add the window again.
- **Grok Bot** (`com.anysphere.sand`) and any other app — a window binding: bundle id and title. On switching, the window with the same title is raised, otherwise the app is simply activated.
- An app that is not running is launched.
- A new task's name is taken from the title without suffixes like " - Claude" and " - Google Chrome". If the current task has no binding, Juggler offers to bind the chat to it.

## Permissions

Juggler never asks for anything on its own — only when binding, when switching to a Chrome tab, or from a button in settings. Control of Terminal is requested only when binding a Terminal window and from the button, never when switching or during the self-test. Without permissions it does not crash, it just does less.

Permission status is shown in Juggler settings, "Permissions" section, along with request buttons.

**Accessibility** is needed to:

- read window titles;
- read the Claude chat URL and the Claude Code session id;
- raise the right window.

How to grant: System Settings → Privacy & Security → Accessibility → enable Juggler. Without this permission Claude and windows bind less well: a link is needed, and switching just activates the app.

**Automation → Google Chrome (Apple Events)** is needed to see Chrome tabs and switch to the bound tab.

- macOS asks for this permission on the first tab binding or from the "Allow…" button in settings. The prompt text comes from `NSAppleEventsUsageDescription`.
- **Without the permission** Juggler cannot see the tab. On switching it reopens the URL, and duplicate tabs pile up in Chrome.
- If access was denied once, macOS never asks again. Enable it manually: System Settings → Privacy & Security → Automation → Juggler → Google Chrome.
- If Juggler is not in that list, reset the decision and bind the tab again:
  ```sh
  tccutil reset AppleEvents com.sefimov.juggler
  ```

**Automation → Terminal (Apple Events)** is needed to bind a Terminal window and tab (window id, tty) and switch to exactly them.

- macOS asks for this permission on the first Terminal window binding or from the "Allow…" button in the "Terminal" row of the "Permissions" section in settings. The status in settings is read without prompting.
- **Without the permission** a Terminal window is bound as an ordinary window, by title. On switching Juggler raises the window with that title (Accessibility is needed) but does not select the tab; the card says the permission is missing.
- If access was denied, enable it manually: System Settings → Privacy & Security → Automation → Juggler → Terminal. If Juggler is not in the list — `tccutil reset AppleEvents com.sefimov.juggler` and the "Allow…" button in settings.

**Permissions lost after a rebuild.** With ad-hoc signing every build has a new signature, and macOS treats it as a different app. Juggler may stay enabled in the Accessibility list yet not work. What to do:

- turn Juggler off and on again in the list, or remove it with the "−" button;
- or reset the permissions entirely:
  ```sh
  tccutil reset Accessibility com.sefimov.juggler
  tccutil reset AppleEvents com.sefimov.juggler
  ```

The reliable fix is a persistent "Juggler Dev" certificate, see the next section.

## Signing: the "Juggler Dev" certificate

With a self-signed certificate the signature stays the same from build to build, so granted permissions survive rebuilds. The certificate is needed only on this Mac; you do not need to pay Apple.

1. Open Keychain Access. Since macOS 15 it is not in Applications; find it with Spotlight or open `/System/Library/CoreServices/Applications/Keychain Access.app`.
2. Keychain Access menu → Certificate Assistant → Create a Certificate…
3. Fill in the fields:
   - Name — `Juggler Dev`;
   - Identity Type — Self Signed Root;
   - Certificate Type — Code Signing.

   Click Create. The certificate goes into the login keychain.
4. Check that the certificate is visible:
   ```sh
   security find-identity -p codesigning
   ```
   A `CSSMERR_TP_NOT_TRUSTED` note does not matter for local signing.
5. Build the app:
   ```sh
   JUGGLER_SIGN_IDENTITY="Juggler Dev" scripts/bundle.sh
   ```
   On the first signing macOS asks whether `codesign` may use the key. Enter your login password and click Always Allow.
6. Check the signature:
   ```sh
   codesign -dv build/Juggler.app
   ```
   It should show `Authority=Juggler Dev`.
7. Grant the permissions again, once. Permissions granted to the ad-hoc build do not apply to the new signature. If something does not work, run `tccutil reset …` from the "Permissions" section.

If `codesign` says it cannot build a chain to a trusted root, open the certificate in Keychain Access. Under Trust, set "Code Signing: Always Trust".

To avoid setting `JUGGLER_SIGN_IDENTITY` every time, add `export JUGGLER_SIGN_IDENTITY="Juggler Dev"` to `~/.zshrc`.

## Debugging bindings: `--probe-frontmost`

```sh
build/Juggler.app/Contents/MacOS/Juggler --probe-frontmost                 # the frontmost window right now
build/Juggler.app/Contents/MacOS/Juggler --probe-frontmost --delay 3       # after 3 s: time to switch to the chat
build/Juggler.app/Contents/MacOS/Juggler --probe-frontmost --app com.google.Chrome  # context of a specific app
build/Juggler.app/Contents/MacOS/Juggler --probe-frontmost --prompt        # allow the system prompt to control Chrome (and Terminal if it is in front)
build/Juggler.app/Contents/MacOS/Juggler --probe-frontmost --app com.apple.Terminal  # Terminal window and tab tty
build/Juggler.app/Contents/MacOS/Juggler --probe-frontmost --app com.openai.codex --window-title "Thread name"  # find a ChatGPT thread by the given title
```

macOS applies the Accessibility permission to `Juggler.app` only if the command is launched via `open`:

```sh
open -n -W --stdout /tmp/probe.json build/Juggler.app --args --probe-frontmost --app com.openai.codex
```

The command prints JSON with three parts:

- `context` — bundle id, title, Chrome tab, chat id, Terminal window (`terminalWindow`: `windowID`, `tty`, `title`);
- `diagnostics` — whether Accessibility is granted, Chrome and Terminal control status (`terminalAutomation`), Claude URL candidates, notes. In `claudeChat`, `read` means the chat id was read, `codeSession` means the Code tab is in front and the session id was read (`context.claudeCodeSessionID`, title in `context.claudeCodeSessionTitle`). For ChatGPT, `chatGPTThread` holds the thread lookup in `session_index.jsonl`: `status` (`found`, `ambiguous`, `notFound`, `noWindowTitle`, `indexMissing`, `indexTooLarge`, `indexUnreadable`), the title searched for, the file path, the thread count, skipped lines and matching threads (`matches`, most recently updated first);
- `capture` — which binding would result.

Without `--prompt` there are no system prompts. Exit code is 0 if the context was read. Permissions are checked for the process the command runs from: from the `.app` — Juggler's, via `swift run` — Terminal's.

## Command Line Tools limitations

Without Xcode the following are unavailable:

- `#Preview` and SwiftUI previews;
- `.xcassets` asset catalogs, so icons are done with SF Symbols or in code;
- `.storyboard` and `.xib`;
- XCTest and Swift Testing, so `swift test` does not work.

How we work around them:

- Logic is checked by the `JugglerChecks` executable target with its own mini runner (`CheckRunner`).
- The package uses `swift-tools-version:5.10` and Swift 5 language mode. This makes Carbon callbacks and AppleScript easier to work with, without Swift 6 strict concurrency checking.
- State uses `ObservableObject` and `@Published`. Macros like `@Observable` have not been tested with the Command Line Tools.
- There are no third-party dependencies.

## Localization

The interface is translated into 12 languages: `ar`, `de`, `en`, `es`, `fr`, `hi`, `it`, `ja`, `ko`, `pt-BR`, `ru`, `zh-Hans`. macOS picks the language from System Settings → General → Language & Region, or from the language chosen for Juggler there. If none of the languages fit, the interface is in English (`CFBundleDevelopmentRegion` is `en`).

- Source strings in the code stay in Russian and serve as translation keys: `String(localized: "Задача \(number)")` or a SwiftUI literal (`Text("…")`, `Button("…")`, `.help("…")`).
- Translations live in `Localization/<language>.lproj/`:
  - `Localizable.strings` — interface strings. Interpolation becomes a format specifier: `Int` → `%lld`, `Int32` → `%d`, anything else → `%@`. If a translation needs a different order, use positional specifiers: `%1$@`, `%2$lld`;
  - `Localizable.stringsdict` — plural forms for the "3 tasks, 1 done" summary;
  - `InfoPlist.strings` — the text of the request to control Chrome.
- `scripts/bundle.sh` copies these folders into the `.app`. Without the `.app` (`swift run`, `JugglerChecks`) there are no tables, so the Russian text is shown. The checks compare exactly that text.
- `scripts/check-localization.py` verifies that every table has exactly the keys from the code with the same specifiers, and that `CFBundleLocalizations` matches the folders. The script is run from `bundle.sh`. `--keys` prints the keys with their location in the code.

### Changing the language in settings

Juggler settings → "Language": "Same as system" and the 12 languages, each labeled with its own name ("Русский", "English", "Deutsch", "日本語" …). The current choice is shown.

- The choice applies to Juggler only: the `AppleLanguages` key in Juggler's own defaults domain `com.sefimov.juggler` (the same as the per-app language in System Settings). The system language is not changed. "Same as system" removes this value. To view it: `defaults read com.sefimov.juggler AppleLanguages`; to reset it manually: `defaults delete com.sefimov.juggler AppleLanguages`.
- The new language takes effect on the next launch. After choosing, the hint "The language will change after a restart" and a "Restart now" button appear: the button quits Juggler and opens it again right away; tasks are preserved (`tasks.json` is written on every change). If you switch back to the language Juggler is running in, the hint disappears.
- The button works only in the built `.app`. Under `swift run` it is disabled; quit and relaunch Juggler manually.
- Language names in the list are not translated; they live in the code (`AppLanguage.all`), not in `Localizable.strings`. A new language must be added both there and to `CFBundleLocalizations`.
- The logic (the list, selection from `AppleLanguages`, writing and clearing, the restart command) is in `Sources/JugglerCore/UI/LanguageSettings.swift`; the checks are in `UIChecks+Language.swift` and use a separate defaults domain, leaving the real settings untouched.

To add or change a string: change the text in the code, then add the key to `Localizable.strings` for all 12 languages (for `ru`, the value equals the key) and run `scripts/check-localization.py`. To add a language: create a `Localization/<language>.lproj` folder with the three files, and add the language to `CFBundleLocalizations` in `scripts/Info.plist` and to `AppLanguage.all` (the picker list in settings).

## Package layout

```
Package.swift
Sources/
  JugglerCore/            library, Foundation only: all testable logic
    Core/                 CORE: model, store, switching, staleness, links, titles
      Model/              JugglerTask, TaskBinding (+ ChromeTabRef, ClaudeChatRef, ClaudeCodeSessionRef,
                          ChatGPTThreadRef, TerminalWindowRef, AppWindowRef), TasksDocument, FrontmostContext
      Store/              TaskStore: tasks.json, atomic writes, backup, quarantine of a corrupt file
      Switching/          TaskCycler (1→2→3→1, skipping "done"), CurrentTaskResolver
      Staleness/          "away N min", staleness levels
      Links/              ChatLinkParser (claude.ai/chat, claude.ai/epitaxy, claude://, UUID, local_<uuid>,
                          codex://threads, claude.ai/share detection), URLNormalizer
      Titles/             TitleCleaner (" - Claude", " - Google Chrome", … suffixes),
                          TerminalTitle (Terminal title without size, shell, user@host)
      Contracts/          ActivationResult, BindingCaptureResult, TransitionCardContent, HotkeyAction
    UI/  Switch/  Bind/   pure logic for the UI, SWITCH, BIND tasks
  Juggler/                the app (SwiftUI + AppKit, MenuBarExtra)
    App/                  CORE/PACK: entry point, AppDelegate, AppModel, protocols, composition root, self-test
    UI/                   UI: UIModule — menu bar and settings scenes
    Switch/               SWITCH: SwitchModule — switcher, card, hotkeys
    Bind/                 BIND: BindModule — window context, binding, activation, permissions
  JugglerChecks/          executable checks
    main.swift            list of suites: Core, UI, Switch, Bind (already listed)
    Harness/              CheckRunner, the CheckSuite protocol
    Core/                 core checks
    UI/  Switch/  Bind/   UIChecks, SwitchChecks, BindChecks
scripts/
  bundle.sh               builds build/Juggler.app, signs, checks, self-tests
  Info.plist              the app's Info.plist template
```

Data is stored in `~/Library/Application Support/Juggler/tasks.json`.

A binding in JSON is `{"kind": "<kind>", "<kind>": {…}}`. Kinds: `chromeTab`, `claudeChat`, `claudeCodeSession`, `chatGPTThread`, `appWindow`. New kinds are only ever added, so files from earlier versions load without loss. An unrecognized kind, for example from a file written by a newer version, becomes "no binding", and the rest of the task's data is kept.

If the file cannot be read at load time:

- A copy of it is saved as `tasks.corrupt-<time>.json`.
- Data is restored from `tasks.backup.json`, i.e. the version before the last write.
- If there is no backup, the app starts with an empty list.

## Extension points and rules for UI, SWITCH, BIND and PACK

Each task works only in its own folders:

| Task | App | Pure logic | Checks |
|---|---|---|---|
| UI | `Sources/Juggler/UI/` | `Sources/JugglerCore/UI/` | `Sources/JugglerChecks/UI/` |
| SWITCH | `Sources/Juggler/Switch/` | `Sources/JugglerCore/Switch/` | `Sources/JugglerChecks/Switch/` |
| BIND | `Sources/Juggler/Bind/` | `Sources/JugglerCore/Bind/` | `Sources/JugglerChecks/Bind/` |
| CORE, PACK | `Sources/Juggler/App/`, `scripts/` | `Sources/JugglerCore/Core/` | `Sources/JugglerChecks/{main.swift,Harness,Core}` |

1. **Protocols** are declared in `Sources/Juggler/App/ExtensionPoints.swift`. All of them are `@MainActor`.
   - BIND implements `FrontmostContextProviding`, `BindingCapturing`, `BindingActivating`, `PermissionsProviding` (together, `BindServices`) and `CurrentChatBinding`. The latter is the "Make current chat a task" scenario (`bindCurrentChat`) and the ⌃⌥§ "Add or remove current window" toggle from the menu and the hotkey (`toggleCurrentChat`).
   - SWITCH implements `TaskSwitching`, `TransitionCardPresenting` and `HotkeyRegistering`.
2. **Module factories are the contract.** The composition root `App/CompositionRoot.swift` (`AppEnvironment`) and the entry point `App/JugglerApp.swift` call only these functions:
   - `BindModule.makeServices()`;
   - `BindModule.makeCurrentChatBinder(model:services:card:toggleHotkey:)`;
   - `BindModule.probeFrontmost(arguments:)`;
   - `BindModule.selfTest()`;
   - `SwitchModule.makeCardPresenter()`;
   - `SwitchModule.makeSwitcher(model:bind:card:)`;
   - `SwitchModule.makeHotkeys()`;
   - `SwitchModule.hotkeySettingsView(environment:)`;
   - `SwitchModule.selfTest()`;
   - `UIModule.scenes(environment:)`;
   - `UIModule.selfTest()`.

   The `*Module.swift` files currently contain stubs. A task replaces their bodies with its own types and keeps the signatures. You may add as many new files to your own folder as you like.
3. **State** is held by `AppModel` (`App/AppModel.swift`), the sole owner of `TasksDocument`.
   - Changes are made only through `model.update { … }`, which saves the document itself.
   - A visit to a task is recorded with `model.markVisited(id)`.
   - Removal with undo — `model.removeTask(id, undoableByToggle:)` and `model.restoreLastRemoved()`; the last removed task is `model.lastRemoved` (in memory only). The logic is `TaskRemoval`, `TaskToggle` and `ExactTaskMatcher` in `Sources/JugglerCore/Core/Toggle/`.
   - The icon shows `model.currentTaskNumber`, i.e. the number of the last active task.
4. **Hotkey and menu actions** go through `AppEnvironment.perform(_ action: HotkeyAction)`.
   - SWITCH calls the handler passed to `HotkeyRegistering.start(handler:)`.
   - `.bindCurrentChat` is ⌃⌥§ "Add or remove current window": `binder.toggleCurrentChat()`. The case name was not changed because it is the key in `hotkeys.json`.
   - UI calls `environment.binder.toggleCurrentWindow()` (the "Add/Remove Current Window" menu item: the undo window is ignored, restoring is a separate item) and `environment.switcher.activateTask(id:)`.
5. **Pure logic** — list operations (UI), card texts and hotkey parsing (SWITCH), AppleScript response parsing and binding selection (BIND). It lives in `Sources/JugglerCore/<Area>/`.
   - Only Foundation may be used.
   - Types must be `public`.
   - The logic works on core types: `TasksDocument`, `FrontmostContext`, etc.

   The app only calls this logic. This is the only way to check it from `JugglerChecks`: the `Juggler` executable target cannot be imported.
6. **Checks** do not need to be registered in `main.swift`; the `UIChecks`, `SwitchChecks` and `BindChecks` suites are already listed there. It is enough to fill in the `run(_ c: CheckRunner)` method in your `Sources/JugglerChecks/<Area>/<Area>Checks.swift`. Available helpers:
   - `c.group("…") { … }`;
   - `c.expect(…)`;
   - `c.expectEqual(…)`;
   - `c.expectNil(…)`.

   Additional files are written as `extension <Area>Checks`.
7. **Core files** (`Core/`, `App/`) are not changed by second-stage tasks. If a change is unavoidable, it must only add new things without changing existing ones, and the coordinator must be told about it. This way UI, SWITCH and BIND merge without conflicts.
8. **The self-test** `--self-test` must not request permissions or show windows. Each area returns `[SelfTestResult]` from its `selfTest()`.
9. **Constraints:**
   - no `#Preview`, `.xcassets`, `.storyboard`/`.xib` or third-party dependencies;
   - interface strings are written in Russian via `String(localized:)` or a SwiftUI literal, with translations in `Localization/*.lproj`, see "Localization";
   - logging goes through `Logger(subsystem: JugglerLog.subsystem, category: "<area>")`.
