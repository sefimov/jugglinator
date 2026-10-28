# Juggler

Приложение для macOS в меню-баре. Показывает список параллельных задач-чатов и переключает их по кругу хоткеем. При переключении открывает привязанный чат в Claude, сессию Claude Code, тред ChatGPT, окно Grok Bot или вкладку Chrome.

- Bundle id: `com.sefimov.juggler`.
- Требуется macOS 14 или новее.
- Интерфейс на русском.

## Быстрый старт

```sh
scripts/bundle.sh            # собрать, подписать и самопроверить build/Juggler.app
open build/Juggler.app       # запустить: в меню-баре появится значок с номером задачи
```

Дальше:

1. Откройте чат в Claude, сессию на вкладке Code в Claude, чат в ChatGPT или Grok Bot, вкладку в Chrome.
2. Нажмите ⌃⌥§ или выберите в меню Juggler «Сделать задачей текущий чат».
3. Повторите для остальных задач.
4. Переключайтесь по кругу хоткеем ⌃§, назад — ⌃⇧§.

При первой привязке Juggler попросит разрешения, подробнее — в разделе «Разрешения». Чтобы разрешения не сбрасывались после каждой пересборки, подпишите приложение сертификатом «Juggler Dev», см. раздел «Подпись».

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

`swift run Juggler` удобен для отладки. Но без `.app` разрешения macOS выдаются Терминалу, а не Juggler, и не работает запуск при входе в систему. Для обычной работы собирайте `.app`.

## Сборка .app

```sh
scripts/bundle.sh                                   # подпись ad-hoc
JUGGLER_SIGN_IDENTITY="Juggler Dev" scripts/bundle.sh  # подпись своим сертификатом
scripts/bundle.sh --no-self-test                    # без запуска самопроверки в конце
JUGGLER_VERSION=0.2.0 scripts/bundle.sh             # своя версия (по умолчанию 0.1.0)
```

Что делает скрипт:

1. Собирает release: `swift build -c release --product Juggler`.
2. Складывает `build/Juggler.app`. `Info.plist` берётся из шаблона `scripts/Info.plist`:
   - `CFBundleIdentifier` — `com.sefimov.juggler`;
   - `LSUIElement` — значка в Dock нет, только меню-бар;
   - `LSMinimumSystemVersion` — 14.0;
   - `NSAppleEventsUsageDescription` — объяснение на русском для запроса управления Chrome;
   - `CFBundleDevelopmentRegion` — `ru` и локализация `ru.lproj`, поэтому системные строки (меню, заголовок окна настроек) тоже на русском;
   - `CFBundleVersion` — число коммитов в `git`.
3. Проверяет `Info.plist` через `plutil -lint`.
4. Подписывает: идентичностью из `JUGGLER_SIGN_IDENTITY`, по умолчанию ad-hoc (`-`).
5. Проверяет подпись: `codesign --verify --strict --verbose=2`.
6. Запускает `build/Juggler.app/Contents/MacOS/Juggler --self-test`.

Любой сбой останавливает скрипт с ненулевым кодом. Папка `build/` в `git` не попадает.

Самопроверку можно запустить и отдельно:

```sh
build/Juggler.app/Contents/MacOS/Juggler --self-test; echo $?
```

Она инициализирует хранилище, корень композиции и модули UI, SWITCH и BIND. Проверяет связку «хоткей → переключатель → карточка», «⌃⌥ → привязка», регистрацию хоткеев Carbon и ключи `Info.plist` собранного `.app`. Окон не показывает и разрешений не запрашивает. Код 0 — всё прошло.

## Запуск

- `open build/Juggler.app` — запустить собранное приложение. Если Juggler уже запущен, сначала закройте его: меню Juggler → «Выйти из Juggler».
- **Запуск при входе в систему** включается в настройках Juggler (меню → «Настройки…»). Работает только из `.app`. Надёжнее всего, если приложение лежит в `/Applications`:
  ```sh
  ditto build/Juggler.app /Applications/Juggler.app
  ```
  Если macOS просит подтверждения, в настройках Juggler появится кнопка «Открыть «Объекты входа»».
- Данные — `~/Library/Application Support/Juggler/tasks.json`, свои хоткеи — `hotkeys.json` там же.

## Хоткеи

| Действие | По умолчанию | Клавиатура ANSI |
|---|---|---|
| Следующая задача | ⌃§ | ⌃` |
| Предыдущая задача | ⌃⇧§ | ⌃⇧` |
| Сделать задачей текущий чат | ⌃⌥§ | ⌃⌥` |

- § — физическая клавиша над Tab, слева от 1. В русской раскладке на ней `<`. Хоткей привязан к самой клавише, а не к символу, поэтому работает и в РУ, и в EN.
- Тип клавиатуры (ISO с § или ANSI с `) Juggler определяет сам и выбирает умолчания под него.
- Порядок переключения фиксированный: 1→2→3→1. Задачи с отметкой «сделано» пропускаются. Текущая задача определяется в момент нажатия по переднему окну или вкладке.
- При переходе на секунду-полторы появляется карточка с номером, названием, заметкой и «не был N мин». Карточка не забирает фокус и пропускает клики.
- **Переназначение:** настройки Juggler → «Хоткеи». Нажмите на поле и затем нужное сочетание, Esc — отмена, «По умолчанию» — вернуть умолчание.
- В `~/Library/Application Support/Juggler/hotkeys.json` хранятся только переназначенные сочетания. Умолчания вычисляются при запуске по типу клавиатуры. Чтобы сбросить всё, закройте Juggler и удалите этот файл.
- Глобальные хоткеи (Carbon) работают только в запущенном приложении. Разрешение Accessibility для самих хоткеев не нужно.

## Привязки

«Сделать задачей текущий чат» смотрит на переднее окно. Если впереди меню Juggler, берётся последнее активное приложение.

- **Google Chrome** (`com.google.Chrome`) — активная вкладка: id, адрес, заголовок. При переходе Juggler ищет вкладку по id, потом по адресу, иначе открывает адрес заново.
- **Claude** (`com.anthropic.claudefordesktop`) — чат по UUID. Juggler пробует прочитать адрес чата через Accessibility. Если не вышло, просит вставить адрес чата: `https://claude.ai/chat/<uuid>`, `claude://claude.ai/chat/<uuid>` или голый UUID. Адрес виден в адресной строке, если открыть чат на claude.ai в браузере. Ссылка «Поделиться» (`claude.ai/share/…`) не подходит: это публичная копия беседы, а не сам чат. Juggler её распознаёт и так и говорит. Открывается ссылкой `claude://claude.ai/chat/<uuid>`.
- **Сессия Claude Code** (вкладка Code в Claude desktop) — сессия по id `local_<uuid>`.
  - На вкладке Code ⌃⌥ и «Сделать задачей текущий чат» привязывают сессию сразу, без диалога. Juggler читает её адрес `https://claude.ai/epitaxy/local_<uuid>` через Accessibility.
  - Название задачи — `title` сессии из `~/Library/Application Support/Claude/claude-code-sessions/…/local_<uuid>.json`. Если файла или названия нет — очищенный заголовок окна, а если и он пустой (у вкладки Code это просто «Claude») — «Сессия Claude Code». Эти файлы Juggler только читает.
  - Открывается ссылкой `claude://claude.ai/epitaxy/local_<uuid>`. Текущая задача определяется по id сессии в переднем окне Claude, поэтому круг 1→2→3→1 работает и между сессиями.
  - В диалоге ссылки сессию можно указать и вручную: `https://claude.ai/epitaxy/local_<uuid>`, `claude://claude.ai/epitaxy/local_<uuid>` или голый `local_<uuid>`.
  - В списке у такой задачи значок терминала и подпись «Claude Code».
  - Без разрешения «Универсальный доступ» id сессии не прочитать: Juggler покажет диалог ссылки.
- **ChatGPT** (`com.openai.codex`, старый `com.openai.chat`) — Juggler просит вставить ссылку `codex://threads/<id>` и открывает тред по ней.
- **Grok Bot** (`com.anysphere.sand`) и любое другое приложение — привязка к окну: bundle id и заголовок. При переходе поднимается окно с тем же заголовком, иначе просто активируется приложение.
- Незапущенное приложение запускается.
- Название новой задачи берётся из заголовка без хвостов вида « - Claude» и « - Google Chrome». Если у текущей задачи нет привязки, Juggler предложит привязать чат к ней.

## Разрешения

Juggler ничего не запрашивает сам по себе — только при привязке, переходе на вкладку Chrome или по кнопке в настройках. Без разрешений он не падает, просто умеет меньше.

Состояние разрешений видно в настройках Juggler, раздел «Разрешения». Там же есть кнопки запроса.

**Универсальный доступ (Accessibility)** нужен, чтобы:

- читать заголовки окон;
- читать адрес чата Claude и id сессии Claude Code;
- поднимать нужное окно.

Как выдать: Системные настройки → Конфиденциальность и безопасность → Универсальный доступ → включить Juggler. Без этого разрешения Claude и окна привязываются хуже: нужна ссылка, а при переходе просто активируется приложение.

**Автоматизация → Google Chrome (Apple Events)** нужна, чтобы видеть вкладки Chrome и переключаться на привязанную вкладку.

- macOS спрашивает это разрешение при первой привязке вкладки или по кнопке «Разрешить…» в настройках. Текст запроса — из `NSAppleEventsUsageDescription`.
- **Без разрешения** Juggler не видит вкладку. При переходе он открывает адрес заново, и в Chrome появляются дубли вкладок.
- Если доступ однажды запретили, macOS больше не спрашивает. Включите его вручную: Системные настройки → Конфиденциальность и безопасность → Автоматизация → Juggler → Google Chrome.
- Если Juggler в этом списке нет, сбросьте решение и привяжите вкладку снова:
  ```sh
  tccutil reset AppleEvents com.sefimov.juggler
  ```

**Разрешения слетели после пересборки.** При подписи ad-hoc у каждой сборки новая подпись, и macOS считает её другим приложением. Juggler может оставаться в списке «Универсальный доступ» включённым, но не работать. Что делать:

- выключите и снова включите Juggler в списке или удалите его кнопкой «−»;
- или сбросьте разрешения целиком:
  ```sh
  tccutil reset Accessibility com.sefimov.juggler
  tccutil reset AppleEvents com.sefimov.juggler
  ```

Надёжное решение — постоянный сертификат «Juggler Dev», см. следующий раздел.

## Подпись: сертификат «Juggler Dev»

С самоподписанным сертификатом подпись одинакова от сборки к сборке. Поэтому выданные разрешения переживают пересборку. Сертификат нужен только на этом маке, платить Apple не нужно.

1. Откройте «Связку ключей» (Keychain Access). С macOS 15 её нет в «Программах», ищите через Spotlight или откройте `/System/Library/CoreServices/Applications/Keychain Access.app`.
2. Меню «Связка ключей» → «Ассистент сертификации» → «Создать сертификат…».
3. Заполните поля:
   - имя — `Juggler Dev`;
   - тип идентификации — «Самоподписанный корневой»;
   - тип сертификата — «Подпись кода».

   Нажмите «Создать». Сертификат попадёт в связку «вход» (login).
4. Проверьте, что сертификат виден:
   ```sh
   security find-identity -p codesigning
   ```
   Пометка `CSSMERR_TP_NOT_TRUSTED` для локальной подписи не мешает.
5. Соберите приложение:
   ```sh
   JUGGLER_SIGN_IDENTITY="Juggler Dev" scripts/bundle.sh
   ```
   При первой подписи macOS спросит, можно ли `codesign` использовать ключ. Введите пароль входа и нажмите «Разрешить всегда».
6. Проверьте подпись:
   ```sh
   codesign -dv build/Juggler.app
   ```
   Должно быть `Authority=Juggler Dev`.
7. Один раз выдайте разрешения заново. Разрешения, выданные ad-hoc-сборке, к новой подписи не относятся. Если что-то не работает, выполните `tccutil reset …` из раздела «Разрешения».

Если `codesign` пишет, что не может построить цепочку до доверенного корня, откройте сертификат в «Связке ключей». В разделе «Доверие» поставьте «Подпись кода: Всегда доверять».

Чтобы `JUGGLER_SIGN_IDENTITY` не задавать каждый раз, добавьте `export JUGGLER_SIGN_IDENTITY="Juggler Dev"` в `~/.zshrc`.

## Отладка привязок: `--probe-frontmost`

```sh
build/Juggler.app/Contents/MacOS/Juggler --probe-frontmost                 # переднее окно сейчас
build/Juggler.app/Contents/MacOS/Juggler --probe-frontmost --delay 3       # через 3 с: успеть переключиться на чат
build/Juggler.app/Contents/MacOS/Juggler --probe-frontmost --app com.google.Chrome  # контекст конкретного приложения
build/Juggler.app/Contents/MacOS/Juggler --probe-frontmost --prompt        # разрешить системный запрос управления Chrome
```

Команда печатает JSON из трёх частей:

- `context` — bundle id, заголовок, вкладка Chrome, id чата;
- `diagnostics` — есть ли Accessibility, статус управления Chrome, кандидаты адреса Claude, заметки. В `claudeChat` значение `read` — прочитан id чата, `codeSession` — впереди вкладка Code и прочитан id сессии (`context.claudeCodeSessionID`, название — `context.claudeCodeSessionTitle`);
- `capture` — какая привязка получилась бы.

Без `--prompt` системных запросов нет. Код выхода 0, если контекст прочитан. Разрешения проверяются у того процесса, из которого запущена команда: из `.app` — у Juggler, через `swift run` — у Терминала.

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
      Model/              JugglerTask, TaskBinding (+ ChromeTabRef, ClaudeChatRef, ClaudeCodeSessionRef,
                          ChatGPTThreadRef, AppWindowRef), TasksDocument, FrontmostContext
      Store/              TaskStore: tasks.json, атомарная запись, резервная копия, карантин битого файла
      Switching/          TaskCycler (1→2→3→1, пропуск «сделано»), CurrentTaskResolver
      Staleness/          «не был N мин», уровни старения
      Links/              ChatLinkParser (claude.ai/chat, claude.ai/epitaxy, claude://, UUID, local_<uuid>,
                          codex://threads, распознавание claude.ai/share), URLNormalizer
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
scripts/
  bundle.sh               сборка build/Juggler.app, подпись, проверки, самопроверка
  Info.plist              шаблон Info.plist приложения
```

Данные хранятся в `~/Library/Application Support/Juggler/tasks.json`.

Привязка в JSON — `{"kind": "<вид>", "<вид>": {…}}`. Виды: `chromeTab`, `claudeChat`, `claudeCodeSession`, `chatGPTThread`, `appWindow`. Новые виды только добавляются, поэтому файлы прежних версий читаются без потерь. Нераспознанный вид, например из файла более новой версии, превращается в «без привязки», а остальные данные задачи сохраняются.

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
| CORE, PACK | `Sources/Juggler/App/`, `scripts/` | `Sources/JugglerCore/Core/` | `Sources/JugglerChecks/{main.swift,Harness,Core}` |

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
