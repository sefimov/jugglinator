import Foundation

/// User-facing BIND texts: the Russian text is the translation key in `Localizable.strings`.
public enum BindTexts {
    public static let accessibilitySettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    public static let automationSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"

    public static var noFrontmostApp: String { loc("Не удалось определить переднее окно. Переключитесь на окно чата и повторите.") }
    public static var frontmostIsJuggler: String { loc("Впереди окно Jugglinator. Переключитесь на окно чата и повторите.") }
    public static var emptyLink: String { loc("Вставьте ссылку на чат.") }
    /// Title of a new session task when the session has no title and the window title is just "Claude".
    public static var defaultSessionTaskTitle: String { loc("Сессия Claude Code") }

    /// Explanation for a pasted "Share" link (`claude.ai/share/…`): what is wrong and what will work.
    public static var shareLinkNotSupported: String { loc("""
        Это ссылка «Поделиться» (claude.ai/share/…). Она ведёт на публичную копию беседы, а не на сам чат, \
        поэтому открыть по ней чат в Claude нельзя. Нужен адрес самого чата: https://claude.ai/chat/<id> — \
        он виден в адресной строке, если открыть чат на claude.ai в браузере.
        """) }

    public static func chromeTabUnavailable(_ status: AutomationStatus?) -> String {
        switch status {
        case .denied?, .requiresConsent?:
            return loc("Нет разрешения управлять Google Chrome, поэтому вкладку не прочитать. \(chromeInstructionsShort)")
        case .noWindow?:
            return loc("В Google Chrome нет открытого окна с вкладкой.")
        case .notRunning?:
            return loc("Google Chrome не запущен.")
        default:
            return loc("Не удалось прочитать активную вкладку Google Chrome.")
        }
    }

    public static func unrecognizedLink(_ expected: BindingSource) -> String {
        switch expected {
        case .chatGPTThread:
            return loc("Ссылка не распознана. Нужна ссылка вида codex://threads/<id>.")
        default:
            return loc("Ссылка не распознана. Нужен адрес чата вида https://claude.ai/chat/<id> или claude://claude.ai/chat/<id>, а для сессии Claude Code — claude://claude.ai/epitaxy/local_<id> или просто local_<id>.")
        }
    }

    // MARK: Link request

    public static func manualLinkTitle(_ source: BindingSource) -> String {
        switch source {
        case .chatGPTThread: return loc("Ссылка на тред ChatGPT")
        case .claudeCodeSession: return loc("Ссылка на сессию Claude Code")
        default: return loc("Ссылка на чат Claude")
        }
    }

    public static func manualLinkMessage(_ source: BindingSource, accessibilityTrusted: Bool) -> String {
        switch source {
        case .chatGPTThread:
            return chatGPTLinkMessage(lookup: nil, accessibilityTrusted: accessibilityTrusted)
        default:
            let reason = accessibilityTrusted
                ? loc("Jugglinator не смог прочитать адрес чата из окна Claude.")
                : loc("Без разрешения «Универсальный доступ» Jugglinator не может прочитать адрес чата из окна Claude.")
            let howTo = loc("""
                Откройте этот чат на claude.ai в браузере, скопируйте адрес из адресной строки \
                (https://claude.ai/chat/<id>) и вставьте его сюда. Ссылки «Поделиться» (claude.ai/share/…) не подходят. \
                Сессия Claude Code (вкладка Code) привязывается сама, если у Jugglinator есть разрешение «Универсальный доступ»; \
                вручную — ссылкой claude://claude.ai/epitaxy/local_<id>.
                """)
            return reason + " " + howTo
        }
    }

    /// Why a ChatGPT thread was not bound automatically and what to do, based on the `session_index.jsonl` lookup.
    public static func chatGPTLinkMessage(lookup: ChatGPTThreadLookup?, accessibilityTrusted: Bool) -> String {
        let howTo = loc("Скопируйте ссылку на тред (codex://threads/<id>) и вставьте её сюда.")
        let title = lookup?.windowTitle ?? ""
        switch lookup?.status {
        case .ambiguous?:
            let count = lookup?.matches.count ?? 0
            return loc("""
                Тредов с названием «\(title)» несколько (\(count)). Вставлена ссылка на последний обновлённый — \
                если это нужный тред, нажмите «Привязать». Иначе вставьте вместо неё ссылку на нужный тред (codex://threads/<id>).
                """)
        case .notFound?:
            return loc("""
                Тред «\(title)» не найден в списке тредов ChatGPT (\(chatGPTIndexPathHint)). \
                Если тред только что создан или переименован, повторите чуть позже.
                """) + " " + howTo
        case .indexMissing?:
            return loc("Список тредов ChatGPT (\(chatGPTIndexPathHint)) не найден, поэтому тред не найти по названию.") + " " + howTo
        case .indexTooLarge?, .indexUnreadable?:
            return loc("Список тредов ChatGPT (\(chatGPTIndexPathHint)) не читается, поэтому тред не найти по названию.") + " " + howTo
        case .found?:
            return howTo
        case .noWindowTitle?, nil:
            let reason = accessibilityTrusted
                ? loc("Jugglinator не смог прочитать заголовок окна ChatGPT, поэтому тред не найти по названию.")
                : loc("Без разрешения «Универсальный доступ» Jugglinator не видит заголовок окна ChatGPT и не может найти тред по названию.")
            return reason + " " + howTo
        }
    }

    static let chatGPTIndexPathHint = "~/.codex/session_index.jsonl"

    public static var manualLinkPlaceholder: String { loc("Вставьте ссылку") }
    public static var bindButton: String { loc("Привязать") }
    public static var bindWindowOnlyButton: String { loc("Привязать только окно") }
    public static var cancelButton: String { loc("Отмена") }

    // MARK: Binding flow

    public static func offerAttachTitle(number: Int, taskTitle: String) -> String {
        loc("Привязать этот чат к задаче \(number) «\(taskTitle)»?")
    }

    public static func offerAttachMessage(suggestedTitle: String) -> String {
        loc("У текущей задачи нет привязки. Можно привязать к ней этот чат или создать новую задачу «\(suggestedTitle)».")
    }

    public static func attachButton(number: Int) -> String { loc("Привязать к задаче \(number)") }
    public static var createNewButton: String { loc("Создать новую задачу") }

    public static func alreadyBound(number: Int) -> String {
        loc("Этот чат уже привязан к задаче \(number). Она отмечена как текущая.")
    }

    public static var bindFailedTitle: String { loc("Не удалось привязать чат") }

    // MARK: Permissions

    public static var accessibilityTitle: String { loc("Нужно разрешение «Универсальный доступ»") }
    public static var accessibilityMessage: String { loc("""
        Jugglinator читает заголовки окон, поднимает нужное окно и пробует прочитать адрес чата Claude. \
        Для этого нужно разрешение «Универсальный доступ».

        Откройте Системные настройки → Конфиденциальность и безопасность → Универсальный доступ \
        и включите Jugglinator. Если Jugglinator уже в списке, но не работает, выключите и снова включите его.
        """) }
    public static var openSettingsButton: String { loc("Открыть настройки") }
    public static var laterButton: String { loc("Позже") }
    public static var continueWithoutButton: String { loc("Продолжить без него") }

    public static var chromeInstructionsShort: String { loc("Разрешите Jugglinator управлять Google Chrome: Системные настройки → Конфиденциальность и безопасность → Автоматизация.") }
    public static var chromeDeniedTitle: String { loc("Jugglinator не может управлять Google Chrome") }
    public static var chromeDeniedMessage: String { loc("""
        macOS запретила Jugglinator управлять Google Chrome (ошибка -1743). Без этого Jugglinator не видит вкладки \
        и не может переключиться на привязанную вкладку — только открыть её адрес заново.

        Как включить:
        1. Откройте Системные настройки → Конфиденциальность и безопасность → Автоматизация.
        2. Найдите Jugglinator и включите переключатель «Google Chrome».
        3. Если Jugglinator в списке нет, выполните в Терминале
           tccutil reset AppleEvents com.sefimov.jugglinator
           и привяжите вкладку снова — macOS спросит разрешение.
        """) }

    public static var terminalDeniedTitle: String { loc("Jugglinator не может управлять Терминалом") }
    public static var terminalDeniedMessage: String { loc("""
        macOS запретила Jugglinator управлять Терминалом (ошибка -1743). Без этого Jugglinator не знает id окна \
        и вкладку (tty): окно Терминала привязывается как обычное окно, по заголовку, а при переходе \
        нужная вкладка не выбирается.

        Как включить:
        1. Откройте Системные настройки → Конфиденциальность и безопасность → Автоматизация.
        2. Найдите Jugglinator и включите переключатель «Терминал».
        3. Если Jugglinator в списке нет, выполните в Терминале
           tccutil reset AppleEvents com.sefimov.jugglinator
           и нажмите «Разрешить…» в настройках Jugglinator (раздел «Разрешения») — macOS спросит разрешение.
        """) }

    // MARK: Activation outcomes

    public static var terminalTabClosed: String { loc("Вкладка Терминала закрыта — открыто её окно.") }
    public static var terminalFoundByTitle: String { loc("Окно Терминала найдено по заголовку.") }
    public static var terminalWindowClosed: String { loc("Окно Терминала закрыто — открыт Терминал.") }
    public static var terminalNoAccess: String { loc("Нет разрешения управлять Терминалом — открыт Терминал.") }
    public static var terminalNoAccessByTitle: String { loc("Нет разрешения управлять Терминалом — окно найдено по заголовку, вкладка не выбрана.") }
    public static var terminalLaunched: String { loc("Терминал был закрыт — он запущен, окна задачи нет.") }

    public static var chromeReopened: String { loc("Вкладка не найдена — адрес открыт заново в Chrome.") }
    public static var chromeReopenedNoAccess: String { loc("Нет разрешения управлять Chrome — адрес открыт заново.") }
    public static var chromeActivatedOnly: String { loc("Вкладка не найдена, открыть её адрес нельзя — открыт Chrome.") }
    public static var windowNotFound: String { loc("Окно с таким заголовком не найдено — открыто приложение.") }
    public static var windowNoAccessibility: String { loc("Без разрешения «Универсальный доступ» окно не поднять — открыто приложение.") }
    public static var appLaunched: String { loc("Приложение было закрыто — оно запущено.") }

    public static func appNotInstalled(_ name: String) -> String { loc("Приложение «\(name)» не найдено.") }
    public static func urlNotHandled(_ name: String) -> String { loc("Не удалось открыть ссылку: приложение «\(name)» не установлено.") }
}
