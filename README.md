# Juggler

Приложение для macOS в меню-баре. Показывает список параллельных задач-чатов и переключает их по кругу хоткеем. При переключении открывает привязанный чат в Claude, ChatGPT, Grok Bot или вкладку Chrome.

- Bundle id: `com.sefimov.juggler`.
- Требуется macOS 14 или новее.
- Интерфейс на русском.

## Сборка и проверки

Нужны только Command Line Tools со Swift 6.x, полный Xcode не требуется.

```sh
swift build                         # собрать все цели
swift run JugglerChecks             # проверки логики: код 0 — всё прошло, 1 — есть провалы
swift run JugglerChecks -v          # печатать каждую прошедшую проверку
swift run JugglerChecks Core Bind   # запустить только выбранные наборы
swift run JugglerChecks --self-fail # заведомый провал: убедиться, что код выхода ненулевой

swift run Juggler                   # запустить приложение в меню-баре (без .app)
swift run Juggler --self-test       # самопроверка компонентов без окон и запросов разрешений
swift run Juggler --probe-frontmost # JSON с контекстом переднего окна
```

Сборку `.app`, подпись и `scripts/bundle.sh` делает задача PACK. Её описание появится здесь позже.

## Ограничения Command Line Tools

Без Xcode недоступны:

- `#Preview` и превью SwiftUI;
- каталоги ресурсов `.xcassets`, поэтому иконки делаются через SF Symbols или кодом;
- `.storyboard` и `.xib`;
- XCTest и Swift Testing, поэтому `swift test` не работает.

Как обходим эти ограничения:

- Логику проверяем исполняемой целью `JugglerChecks` с собственным мини-раннером (`CheckRunner`).
- Пакет использует `swift-tools-version:5.10`, язык Swift 5. Так проще работать с Carbon-колбэками и AppleScript без строгой проверки параллелизма Swift 6.
- Для состояния используем `ObservableObject` и `@Published`. Макросы вроде `@Observable` на Command Line Tools не проверялись.
- Сторонних зависимостей нет.

## Структура пакета

```
Package.swift
Sources/
  JugglerCore/            библиотека, только Foundation: вся проверяемая логика
    Core/                 CORE: модель, хранилище, переключение, старение, ссылки, заголовки
      Model/              JugglerTask, TaskBinding (+ ChromeTabRef, ClaudeChatRef,
                          ChatGPTThreadRef, AppWindowRef), TasksDocument, FrontmostContext
      Store/              TaskStore: tasks.json, атомарная запись, резервная копия, карантин битого файла
      Switching/          TaskCycler (1→2→3→1, пропуск «сделано»), CurrentTaskResolver
      Staleness/          «не был N мин», уровни старения
      Links/              ChatLinkParser (claude.ai/chat, claude://, UUID, codex://threads), URLNormalizer
      Titles/             TitleCleaner (хвосты « - Claude», « - Google Chrome», …)
      Contracts/          ActivationResult, BindingCaptureResult, TransitionCardContent, HotkeyAction
    UI/  Switch/  Bind/   чистая логика задач UI, SWITCH, BIND
  Juggler/                приложение (SwiftUI + AppKit, MenuBarExtra)
    App/                  CORE/PACK: точка входа, AppDelegate, AppModel, протоколы, корень композиции, самопроверка
    UI/                   UI: UIModule — сцены меню-бара и настроек
    Switch/               SWITCH: SwitchModule — переключатель, карточка, хоткеи
    Bind/                 BIND: BindModule — контекст окна, привязка, активация, разрешения
  JugglerChecks/          исполняемые проверки
    main.swift            список наборов: Core, UI, Switch, Bind (уже перечислены)
    Harness/              CheckRunner, протокол CheckSuite
    Core/                 проверки ядра
    UI/  Switch/  Bind/   UIChecks, SwitchChecks, BindChecks
```

Данные хранятся в `~/Library/Application Support/Juggler/tasks.json`.

Если файл не читается при загрузке:

- Его копия сохраняется как `tasks.corrupt-<время>.json`.
- Данные восстанавливаются из `tasks.backup.json`, то есть из версии перед последней записью.
- Если резервной копии нет, приложение начинает с пустого списка.

## Точки расширения и правила для UI, SWITCH, BIND и PACK

Каждая задача работает только в своих папках:

| Задача | Приложение | Чистая логика | Проверки |
|---|---|---|---|
| UI | `Sources/Juggler/UI/` | `Sources/JugglerCore/UI/` | `Sources/JugglerChecks/UI/` |
| SWITCH | `Sources/Juggler/Switch/` | `Sources/JugglerCore/Switch/` | `Sources/JugglerChecks/Switch/` |
| BIND | `Sources/Juggler/Bind/` | `Sources/JugglerCore/Bind/` | `Sources/JugglerChecks/Bind/` |
| CORE, PACK | `Sources/Juggler/App/` | `Sources/JugglerCore/Core/` | `Sources/JugglerChecks/{main.swift,Harness,Core}` |

1. **Протоколы** описаны в `Sources/Juggler/App/ExtensionPoints.swift`. Все они `@MainActor`.
   - BIND реализует `FrontmostContextProviding`, `BindingCapturing`, `BindingActivating`, `PermissionsProviding` (вместе это `BindServices`) и `CurrentChatBinding`. Последний — сценарий «Сделать задачей текущий чат» из меню и по ⌃⌥.
   - SWITCH реализует `TaskSwitching`, `TransitionCardPresenting` и `HotkeyRegistering`.
2. **Фабрики модулей — это контракт.** Корень композиции `App/CompositionRoot.swift` (`AppEnvironment`) и точка входа `App/JugglerApp.swift` вызывают только эти функции:
   - `BindModule.makeServices()`;
   - `BindModule.makeCurrentChatBinder(model:services:)`;
   - `BindModule.probeFrontmost(arguments:)`;
   - `BindModule.selfTest()`;
   - `SwitchModule.makeCardPresenter()`;
   - `SwitchModule.makeSwitcher(model:bind:card:)`;
   - `SwitchModule.makeHotkeys()`;
   - `SwitchModule.hotkeySettingsView(environment:)`;
   - `SwitchModule.selfTest()`;
   - `UIModule.scenes(environment:)`;
   - `UIModule.selfTest()`.

   Сейчас в файлах `*Module.swift` лежат заглушки. Задача заменяет их тела своими типами, а сигнатуры сохраняет. Новые файлы можно добавлять в свою папку сколько угодно.
3. **Состояние** хранит `AppModel` (`App/AppModel.swift`), единственный владелец `TasksDocument`.
   - Изменения делаются только через `model.update { … }`, который сам сохраняет документ.
   - Заход в задачу отмечается через `model.markVisited(id)`.
   - Иконка показывает `model.currentTaskNumber`, то есть номер последней активной задачи.
4. **Действия хоткеев и меню** идут через `AppEnvironment.perform(_ action: HotkeyAction)`.
   - SWITCH вызывает переданный в `HotkeyRegistering.start(handler:)` обработчик.
   - UI вызывает `environment.perform(.bindCurrentChat)` и `environment.switcher.activateTask(id:)`.
5. **Чистая логика** — операции со списком (UI), тексты карточки и разбор хоткея (SWITCH), разбор ответа AppleScript и выбор привязки (BIND). Она живёт в `Sources/JugglerCore/<Область>/`.
   - Можно использовать только Foundation.
   - Типы должны быть `public`.
   - Логика работает над типами ядра: `TasksDocument`, `FrontmostContext` и т. д.

   Приложение лишь вызывает эту логику. Только так её можно проверить из `JugglerChecks`: исполняемую цель `Juggler` импортировать нельзя.
6. **Проверки** регистрировать в `main.swift` не нужно, наборы `UIChecks`, `SwitchChecks` и `BindChecks` там уже перечислены. Достаточно наполнить метод `run(_ c: CheckRunner)` в своём `Sources/JugglerChecks/<Область>/<Область>Checks.swift`. Для этого есть:
   - `c.group("…") { … }`;
   - `c.expect(…)`;
   - `c.expectEqual(…)`;
   - `c.expectNil(…)`.

   Дополнительные файлы оформляются как `extension <Область>Checks`.
7. **Файлы ядра** (`Core/`, `App/`) задачи второго этапа не меняют. Если без правки не обойтись, она должна только добавлять новое, не меняя существующего, и о ней нужно сообщить координатору. Так UI, SWITCH и BIND сливаются без конфликтов.
8. **Самопроверка** `--self-test` не должна запрашивать разрешения или показывать окна. Каждая область возвращает `[SelfTestResult]` из своего `selfTest()`.
9. **Ограничения:**
   - нельзя использовать `#Preview`, `.xcassets`, `.storyboard`/`.xib` и сторонние зависимости;
   - весь интерфейс на русском;
   - журнал пишется через `Logger(subsystem: JugglerLog.subsystem, category: "<область>")`.
