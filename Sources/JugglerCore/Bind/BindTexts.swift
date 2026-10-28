import Foundation

/// Тексты BIND для пользователя (на русском).
public enum BindTexts {
    public static let accessibilitySettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    public static let automationSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"

    public static let noFrontmostApp = "Не удалось определить переднее окно. Переключитесь на окно чата и повторите."
    public static let frontmostIsJuggler = "Впереди окно Juggler. Переключитесь на окно чата и повторите."
    public static let emptyLink = "Вставьте ссылку на чат."
    /// Название новой задачи-сессии, если у сессии нет названия, а заголовок окна — просто «Claude».
    public static let defaultSessionTaskTitle = "Сессия Claude Code"

    /// Пояснение к вставленной ссылке «Поделиться» (`claude.ai/share/…`): что не так и что подойдёт.
    public static let shareLinkNotSupported = """
        Это ссылка «Поделиться» (claude.ai/share/…). Она ведёт на публичную копию беседы, а не на сам чат, \
        поэтому открыть по ней чат в Claude нельзя. Нужен адрес самого чата: https://claude.ai/chat/<id> — \
        он виден в адресной строке, если открыть чат на claude.ai в браузере.
        """

    public static func chromeTabUnavailable(_ status: AutomationStatus?) -> String {
        switch status {
        case .denied?, .requiresConsent?:
            return "Нет разрешения управлять Google Chrome, поэтому вкладку не прочитать. " + chromeInstructionsShort
        case .noWindow?:
            return "В Google Chrome нет открытого окна с вкладкой."
        case .notRunning?:
            return "Google Chrome не запущен."
        default:
            return "Не удалось прочитать активную вкладку Google Chrome."
        }
    }

    public static func unrecognizedLink(_ expected: BindingSource) -> String {
        switch expected {
        case .chatGPTThread:
            return "Ссылка не распознана. Нужна ссылка вида codex://threads/<id>."
        default:
            return "Ссылка не распознана. Нужен адрес чата вида https://claude.ai/chat/<id> или claude://claude.ai/chat/<id>, "
                + "а для сессии Claude Code — claude://claude.ai/epitaxy/local_<id> или просто local_<id>."
        }
    }

    // MARK: Запрос ссылки

    public static func manualLinkTitle(_ source: BindingSource) -> String {
        switch source {
        case .chatGPTThread: return "Ссылка на тред ChatGPT"
        case .claudeCodeSession: return "Ссылка на сессию Claude Code"
        default: return "Ссылка на чат Claude"
        }
    }

    public static func manualLinkMessage(_ source: BindingSource, accessibilityTrusted: Bool) -> String {
        switch source {
        case .chatGPTThread:
            return chatGPTLinkMessage(lookup: nil, accessibilityTrusted: accessibilityTrusted)
        default:
            let reason = accessibilityTrusted
                ? "Juggler не смог прочитать адрес чата из окна Claude."
                : "Без разрешения «Универсальный доступ» Juggler не может прочитать адрес чата из окна Claude."
            return reason + " Откройте этот чат на claude.ai в браузере, скопируйте адрес из адресной строки "
                + "(https://claude.ai/chat/<id>) и вставьте его сюда. Ссылки «Поделиться» (claude.ai/share/…) не подходят. "
                + "Сессия Claude Code (вкладка Code) привязывается сама, если у Juggler есть разрешение «Универсальный доступ»; "
                + "вручную — ссылкой claude://claude.ai/epitaxy/local_<id>."
        }
    }

    /// Почему тред ChatGPT не привязался сам и что делать: по итогу поиска в `session_index.jsonl`.
    public static func chatGPTLinkMessage(lookup: ChatGPTThreadLookup?, accessibilityTrusted: Bool) -> String {
        let howTo = "Скопируйте ссылку на тред (codex://threads/<id>) и вставьте её сюда."
        let title = lookup?.windowTitle ?? ""
        switch lookup?.status {
        case .ambiguous?:
            let count = lookup?.matches.count ?? 0
            return "Тредов с названием «\(title)» несколько (\(count)). Вставлена ссылка на последний обновлённый — "
                + "если это нужный тред, нажмите «Привязать». Иначе вставьте вместо неё ссылку на нужный тред (codex://threads/<id>)."
        case .notFound?:
            return "Тред «\(title)» не найден в списке тредов ChatGPT (\(chatGPTIndexPathHint)). "
                + "Если тред только что создан или переименован, повторите чуть позже. " + howTo
        case .indexMissing?:
            return "Список тредов ChatGPT (\(chatGPTIndexPathHint)) не найден, поэтому тред не найти по названию. " + howTo
        case .indexTooLarge?, .indexUnreadable?:
            return "Список тредов ChatGPT (\(chatGPTIndexPathHint)) не читается, поэтому тред не найти по названию. " + howTo
        case .found?:
            return howTo
        case .noWindowTitle?, nil:
            let reason = accessibilityTrusted
                ? "Juggler не смог прочитать заголовок окна ChatGPT, поэтому тред не найти по названию."
                : "Без разрешения «Универсальный доступ» Juggler не видит заголовок окна ChatGPT и не может найти тред по названию."
            return reason + " " + howTo
        }
    }

    static let chatGPTIndexPathHint = "~/.codex/session_index.jsonl"

    public static let manualLinkPlaceholder = "Вставьте ссылку"
    public static let bindButton = "Привязать"
    public static let bindWindowOnlyButton = "Привязать только окно"
    public static let cancelButton = "Отмена"

    // MARK: Сценарий привязки

    public static func offerAttachTitle(number: Int, taskTitle: String) -> String {
        "Привязать этот чат к задаче \(number) «\(taskTitle)»?"
    }

    public static func offerAttachMessage(suggestedTitle: String) -> String {
        "У текущей задачи нет привязки. Можно привязать к ней этот чат или создать новую задачу «\(suggestedTitle)»."
    }

    public static func attachButton(number: Int) -> String { "Привязать к задаче \(number)" }
    public static let createNewButton = "Создать новую задачу"

    public static func alreadyBound(number: Int) -> String {
        "Этот чат уже привязан к задаче \(number). Она отмечена как текущая."
    }

    public static let bindFailedTitle = "Не удалось привязать чат"

    // MARK: Разрешения

    public static let accessibilityTitle = "Нужно разрешение «Универсальный доступ»"
    public static let accessibilityMessage = """
        Juggler читает заголовки окон, поднимает нужное окно и пробует прочитать адрес чата Claude. \
        Для этого нужно разрешение «Универсальный доступ».

        Откройте Системные настройки → Конфиденциальность и безопасность → Универсальный доступ \
        и включите Juggler. Если Juggler уже в списке, но не работает, выключите и снова включите его.
        """
    public static let openSettingsButton = "Открыть настройки"
    public static let laterButton = "Позже"
    public static let continueWithoutButton = "Продолжить без него"

    public static let chromeInstructionsShort = "Разрешите Juggler управлять Google Chrome: Системные настройки → Конфиденциальность и безопасность → Автоматизация."
    public static let chromeDeniedTitle = "Juggler не может управлять Google Chrome"
    public static let chromeDeniedMessage = """
        macOS запретила Juggler управлять Google Chrome (ошибка -1743). Без этого Juggler не видит вкладки \
        и не может переключиться на привязанную вкладку — только открыть её адрес заново.

        Как включить:
        1. Откройте Системные настройки → Конфиденциальность и безопасность → Автоматизация.
        2. Найдите Juggler и включите переключатель «Google Chrome».
        3. Если Juggler в списке нет, выполните в Терминале
           tccutil reset AppleEvents com.sefimov.juggler
           и привяжите вкладку снова — macOS спросит разрешение.
        """

    public static let terminalDeniedTitle = "Juggler не может управлять Терминалом"
    public static let terminalDeniedMessage = """
        macOS запретила Juggler управлять Терминалом (ошибка -1743). Без этого Juggler не знает id окна \
        и вкладку (tty): окно Терминала привязывается как обычное окно, по заголовку, а при переходе \
        нужная вкладка не выбирается.

        Как включить:
        1. Откройте Системные настройки → Конфиденциальность и безопасность → Автоматизация.
        2. Найдите Juggler и включите переключатель «Терминал».
        3. Если Juggler в списке нет, выполните в Терминале
           tccutil reset AppleEvents com.sefimov.juggler
           и нажмите «Разрешить…» в настройках Juggler (раздел «Разрешения») — macOS спросит разрешение.
        """

    // MARK: Итоги активации

    public static let terminalTabClosed = "Вкладка Терминала закрыта — открыто её окно."
    public static let terminalFoundByTitle = "Окно Терминала найдено по заголовку."
    public static let terminalWindowClosed = "Окно Терминала закрыто — открыт Терминал."
    public static let terminalNoAccess = "Нет разрешения управлять Терминалом — открыт Терминал."
    public static let terminalNoAccessByTitle = "Нет разрешения управлять Терминалом — окно найдено по заголовку, вкладка не выбрана."
    public static let terminalLaunched = "Терминал был закрыт — он запущен, окна задачи нет."

    public static let chromeReopened = "Вкладка не найдена — адрес открыт заново в Chrome."
    public static let chromeReopenedNoAccess = "Нет разрешения управлять Chrome — адрес открыт заново."
    public static let chromeActivatedOnly = "Вкладка не найдена, открыть её адрес нельзя — открыт Chrome."
    public static let windowNotFound = "Окно с таким заголовком не найдено — открыто приложение."
    public static let windowNoAccessibility = "Без разрешения «Универсальный доступ» окно не поднять — открыто приложение."
    public static let appLaunched = "Приложение было закрыто — оно запущено."

    public static func appNotInstalled(_ name: String) -> String { "Приложение «\(name)» не найдено." }
    public static func urlNotHandled(_ name: String) -> String { "Не удалось открыть ссылку: приложение «\(name)» не установлено." }
}
