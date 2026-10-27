import Foundation

/// Тексты BIND для пользователя (на русском).
public enum BindTexts {
    public static let accessibilitySettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    public static let automationSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"

    public static let noFrontmostApp = "Не удалось определить переднее окно. Переключитесь на окно чата и повторите."
    public static let frontmostIsJuggler = "Впереди окно Juggler. Переключитесь на окно чата и повторите."
    public static let emptyLink = "Вставьте ссылку на чат."

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
            return "Ссылка не распознана. Нужна ссылка вида https://claude.ai/chat/<id> или claude://claude.ai/chat/<id>."
        }
    }

    // MARK: Запрос ссылки

    public static func manualLinkTitle(_ source: BindingSource) -> String {
        switch source {
        case .chatGPTThread: return "Ссылка на тред ChatGPT"
        default: return "Ссылка на чат Claude"
        }
    }

    public static func manualLinkMessage(_ source: BindingSource, accessibilityTrusted: Bool) -> String {
        switch source {
        case .chatGPTThread:
            return "Juggler не умеет сам читать id треда ChatGPT. Скопируйте ссылку на тред (codex://threads/<id>) и вставьте её сюда."
        default:
            let reason = accessibilityTrusted
                ? "Juggler не смог прочитать адрес чата из окна Claude."
                : "Без разрешения «Универсальный доступ» Juggler не может прочитать адрес чата из окна Claude."
            return reason + " Скопируйте ссылку на чат (Поделиться → Копировать ссылку или адрес claude.ai/chat/…) и вставьте её сюда."
        }
    }

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

    // MARK: Итоги активации

    public static let chromeReopened = "Вкладка не найдена — адрес открыт заново в Chrome."
    public static let chromeReopenedNoAccess = "Нет разрешения управлять Chrome — адрес открыт заново."
    public static let chromeActivatedOnly = "Вкладка не найдена, открыть её адрес нельзя — открыт Chrome."
    public static let windowNotFound = "Окно с таким заголовком не найдено — открыто приложение."
    public static let windowNoAccessibility = "Без разрешения «Универсальный доступ» окно не поднять — открыто приложение."
    public static let appLaunched = "Приложение было закрыто — оно запущено."

    public static func appNotInstalled(_ name: String) -> String { "Приложение «\(name)» не найдено." }
    public static func urlNotHandled(_ name: String) -> String { "Не удалось открыть ссылку: приложение «\(name)» не установлено." }
}
