import Foundation

/// Тексты BIND для пользователя: русский текст — ключ перевода в `Localizable.strings`.
public enum BindTexts {
    public static let accessibilitySettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    public static let automationSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"

    public static let noFrontmostApp = String(localized: "Не удалось определить переднее окно. Переключитесь на окно чата и повторите.")
    public static let frontmostIsJuggler = String(localized: "Впереди окно Juggler. Переключитесь на окно чата и повторите.")
    public static let emptyLink = String(localized: "Вставьте ссылку на чат.")
    /// Название новой задачи-сессии, если у сессии нет названия, а заголовок окна — просто «Claude».
    public static let defaultSessionTaskTitle = String(localized: "Сессия Claude Code")

    /// Пояснение к вставленной ссылке «Поделиться» (`claude.ai/share/…`): что не так и что подойдёт.
    public static let shareLinkNotSupported = String(localized: """
        Это ссылка «Поделиться» (claude.ai/share/…). Она ведёт на публичную копию беседы, а не на сам чат, \
        поэтому открыть по ней чат в Claude нельзя. Нужен адрес самого чата: https://claude.ai/chat/<id> — \
        он виден в адресной строке, если открыть чат на claude.ai в браузере.
        """)

    public static func chromeTabUnavailable(_ status: AutomationStatus?) -> String {
        switch status {
        case .denied?, .requiresConsent?:
            return String(localized: "Нет разрешения управлять Google Chrome, поэтому вкладку не прочитать. \(chromeInstructionsShort)")
        case .noWindow?:
            return String(localized: "В Google Chrome нет открытого окна с вкладкой.")
        case .notRunning?:
            return String(localized: "Google Chrome не запущен.")
        default:
            return String(localized: "Не удалось прочитать активную вкладку Google Chrome.")
        }
    }

    public static func unrecognizedLink(_ expected: BindingSource) -> String {
        switch expected {
        case .chatGPTThread:
            return String(localized: "Ссылка не распознана. Нужна ссылка вида codex://threads/<id>.")
        default:
            return String(localized: "Ссылка не распознана. Нужен адрес чата вида https://claude.ai/chat/<id> или claude://claude.ai/chat/<id>, а для сессии Claude Code — claude://claude.ai/epitaxy/local_<id> или просто local_<id>.")
        }
    }

    // MARK: Запрос ссылки

    public static func manualLinkTitle(_ source: BindingSource) -> String {
        switch source {
        case .chatGPTThread: return String(localized: "Ссылка на тред ChatGPT")
        case .claudeCodeSession: return String(localized: "Ссылка на сессию Claude Code")
        default: return String(localized: "Ссылка на чат Claude")
        }
    }

    public static func manualLinkMessage(_ source: BindingSource, accessibilityTrusted: Bool) -> String {
        switch source {
        case .chatGPTThread:
            return chatGPTLinkMessage(lookup: nil, accessibilityTrusted: accessibilityTrusted)
        default:
            let reason = accessibilityTrusted
                ? String(localized: "Juggler не смог прочитать адрес чата из окна Claude.")
                : String(localized: "Без разрешения «Универсальный доступ» Juggler не может прочитать адрес чата из окна Claude.")
            let howTo = String(localized: """
                Откройте этот чат на claude.ai в браузере, скопируйте адрес из адресной строки \
                (https://claude.ai/chat/<id>) и вставьте его сюда. Ссылки «Поделиться» (claude.ai/share/…) не подходят. \
                Сессия Claude Code (вкладка Code) привязывается сама, если у Juggler есть разрешение «Универсальный доступ»; \
                вручную — ссылкой claude://claude.ai/epitaxy/local_<id>.
                """)
            return reason + " " + howTo
        }
    }

    /// Почему тред ChatGPT не привязался сам и что делать: по итогу поиска в `session_index.jsonl`.
    public static func chatGPTLinkMessage(lookup: ChatGPTThreadLookup?, accessibilityTrusted: Bool) -> String {
        let howTo = String(localized: "Скопируйте ссылку на тред (codex://threads/<id>) и вставьте её сюда.")
        let title = lookup?.windowTitle ?? ""
        switch lookup?.status {
        case .ambiguous?:
            let count = lookup?.matches.count ?? 0
            return String(localized: """
                Тредов с названием «\(title)» несколько (\(count)). Вставлена ссылка на последний обновлённый — \
                если это нужный тред, нажмите «Привязать». Иначе вставьте вместо неё ссылку на нужный тред (codex://threads/<id>).
                """)
        case .notFound?:
            return String(localized: """
                Тред «\(title)» не найден в списке тредов ChatGPT (\(chatGPTIndexPathHint)). \
                Если тред только что создан или переименован, повторите чуть позже.
                """) + " " + howTo
        case .indexMissing?:
            return String(localized: "Список тредов ChatGPT (\(chatGPTIndexPathHint)) не найден, поэтому тред не найти по названию.") + " " + howTo
        case .indexTooLarge?, .indexUnreadable?:
            return String(localized: "Список тредов ChatGPT (\(chatGPTIndexPathHint)) не читается, поэтому тред не найти по названию.") + " " + howTo
        case .found?:
            return howTo
        case .noWindowTitle?, nil:
            let reason = accessibilityTrusted
                ? String(localized: "Juggler не смог прочитать заголовок окна ChatGPT, поэтому тред не найти по названию.")
                : String(localized: "Без разрешения «Универсальный доступ» Juggler не видит заголовок окна ChatGPT и не может найти тред по названию.")
            return reason + " " + howTo
        }
    }

    static let chatGPTIndexPathHint = "~/.codex/session_index.jsonl"

    public static let manualLinkPlaceholder = String(localized: "Вставьте ссылку")
    public static let bindButton = String(localized: "Привязать")
    public static let bindWindowOnlyButton = String(localized: "Привязать только окно")
    public static let cancelButton = String(localized: "Отмена")

    // MARK: Сценарий привязки

    public static func offerAttachTitle(number: Int, taskTitle: String) -> String {
        String(localized: "Привязать этот чат к задаче \(number) «\(taskTitle)»?")
    }

    public static func offerAttachMessage(suggestedTitle: String) -> String {
        String(localized: "У текущей задачи нет привязки. Можно привязать к ней этот чат или создать новую задачу «\(suggestedTitle)».")
    }

    public static func attachButton(number: Int) -> String { String(localized: "Привязать к задаче \(number)") }
    public static let createNewButton = String(localized: "Создать новую задачу")

    public static func alreadyBound(number: Int) -> String {
        String(localized: "Этот чат уже привязан к задаче \(number). Она отмечена как текущая.")
    }

    public static let bindFailedTitle = String(localized: "Не удалось привязать чат")

    // MARK: Разрешения

    public static let accessibilityTitle = String(localized: "Нужно разрешение «Универсальный доступ»")
    public static let accessibilityMessage = String(localized: """
        Juggler читает заголовки окон, поднимает нужное окно и пробует прочитать адрес чата Claude. \
        Для этого нужно разрешение «Универсальный доступ».

        Откройте Системные настройки → Конфиденциальность и безопасность → Универсальный доступ \
        и включите Juggler. Если Juggler уже в списке, но не работает, выключите и снова включите его.
        """)
    public static let openSettingsButton = String(localized: "Открыть настройки")
    public static let laterButton = String(localized: "Позже")
    public static let continueWithoutButton = String(localized: "Продолжить без него")

    public static let chromeInstructionsShort = String(localized: "Разрешите Juggler управлять Google Chrome: Системные настройки → Конфиденциальность и безопасность → Автоматизация.")
    public static let chromeDeniedTitle = String(localized: "Juggler не может управлять Google Chrome")
    public static let chromeDeniedMessage = String(localized: """
        macOS запретила Juggler управлять Google Chrome (ошибка -1743). Без этого Juggler не видит вкладки \
        и не может переключиться на привязанную вкладку — только открыть её адрес заново.

        Как включить:
        1. Откройте Системные настройки → Конфиденциальность и безопасность → Автоматизация.
        2. Найдите Juggler и включите переключатель «Google Chrome».
        3. Если Juggler в списке нет, выполните в Терминале
           tccutil reset AppleEvents com.sefimov.juggler
           и привяжите вкладку снова — macOS спросит разрешение.
        """)

    public static let terminalDeniedTitle = String(localized: "Juggler не может управлять Терминалом")
    public static let terminalDeniedMessage = String(localized: """
        macOS запретила Juggler управлять Терминалом (ошибка -1743). Без этого Juggler не знает id окна \
        и вкладку (tty): окно Терминала привязывается как обычное окно, по заголовку, а при переходе \
        нужная вкладка не выбирается.

        Как включить:
        1. Откройте Системные настройки → Конфиденциальность и безопасность → Автоматизация.
        2. Найдите Juggler и включите переключатель «Терминал».
        3. Если Juggler в списке нет, выполните в Терминале
           tccutil reset AppleEvents com.sefimov.juggler
           и нажмите «Разрешить…» в настройках Juggler (раздел «Разрешения») — macOS спросит разрешение.
        """)

    // MARK: Итоги активации

    public static let terminalTabClosed = String(localized: "Вкладка Терминала закрыта — открыто её окно.")
    public static let terminalFoundByTitle = String(localized: "Окно Терминала найдено по заголовку.")
    public static let terminalWindowClosed = String(localized: "Окно Терминала закрыто — открыт Терминал.")
    public static let terminalNoAccess = String(localized: "Нет разрешения управлять Терминалом — открыт Терминал.")
    public static let terminalNoAccessByTitle = String(localized: "Нет разрешения управлять Терминалом — окно найдено по заголовку, вкладка не выбрана.")
    public static let terminalLaunched = String(localized: "Терминал был закрыт — он запущен, окна задачи нет.")

    public static let chromeReopened = String(localized: "Вкладка не найдена — адрес открыт заново в Chrome.")
    public static let chromeReopenedNoAccess = String(localized: "Нет разрешения управлять Chrome — адрес открыт заново.")
    public static let chromeActivatedOnly = String(localized: "Вкладка не найдена, открыть её адрес нельзя — открыт Chrome.")
    public static let windowNotFound = String(localized: "Окно с таким заголовком не найдено — открыто приложение.")
    public static let windowNoAccessibility = String(localized: "Без разрешения «Универсальный доступ» окно не поднять — открыто приложение.")
    public static let appLaunched = String(localized: "Приложение было закрыто — оно запущено.")

    public static func appNotInstalled(_ name: String) -> String { String(localized: "Приложение «\(name)» не найдено.") }
    public static func urlNotHandled(_ name: String) -> String { String(localized: "Не удалось открыть ссылку: приложение «\(name)» не установлено.") }
}
