import Foundation

/// Определение текущей задачи по контексту переднего окна.
///
/// Каждая привязка получает оценку совпадения с контекстом; побеждает наибольшая.
/// При равенстве выигрывает `fallbackID` (последняя активная задача), если она среди
/// лучших, иначе — первая по порядку списка. Отметка «сделано» не мешает совпадению:
/// пропуск сделанных — забота `TaskCycler`.
public enum CurrentTaskResolver {
    /// Сила совпадения. Значения упорядочены: точный id важнее адреса, адрес важнее заголовка.
    public enum Score: Int, Comparable, Sendable {
        case none = 0
        /// То же приложение, заголовок не совпал или неизвестен.
        case sameApp = 20
        /// То же приложение и тот же очищенный заголовок окна.
        case sameTitle = 50
        /// Тот же адрес вкладки (без учёта фрагмента, регистра хоста и хвостового «/»).
        case sameURL = 80
        /// Тот же id: вкладки Chrome, чата Claude или треда ChatGPT.
        case sameID = 100

        public static func < (lhs: Score, rhs: Score) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Задача, соответствующая переднему окну; если совпадений нет — `fallbackID`
    /// (если такая задача есть в списке), иначе `nil`.
    public static func resolve(context: FrontmostContext, tasks: [JugglerTask], fallbackID: UUID? = nil) -> UUID? {
        if let matched = match(context: context, tasks: tasks, fallbackID: fallbackID) {
            return matched
        }
        guard let fallbackID, tasks.contains(where: { $0.id == fallbackID }) else { return nil }
        return fallbackID
    }

    /// Только совпадение по контексту, без запасного варианта.
    public static func match(context: FrontmostContext, tasks: [JugglerTask], fallbackID: UUID? = nil) -> UUID? {
        var best = Score.none
        var candidates: [UUID] = []
        for task in tasks {
            guard let binding = task.binding else { continue }
            let s = score(binding, against: context)
            guard s > .none else { continue }
            if s > best {
                best = s
                candidates = [task.id]
            } else if s == best {
                candidates.append(task.id)
            }
        }
        guard !candidates.isEmpty else { return nil }
        if let fallbackID, candidates.contains(fallbackID) { return fallbackID }
        return candidates.first
    }

    public static func score(_ binding: TaskBinding, against context: FrontmostContext) -> Score {
        switch binding {
        case .chromeTab(let ref):
            guard let tab = context.chromeTab else { return .none }
            if let a = ref.tabID, let b = tab.tabID, a == b { return .sameID }
            if !ref.url.isEmpty, URLNormalizer.normalize(ref.url) == URLNormalizer.normalize(tab.url) { return .sameURL }
            return .none

        case .claudeChat(let ref):
            let id = ref.conversationID.lowercased()
            if let current = context.claudeConversationID?.lowercased(), current == id { return .sameID }
            // Тот же чат, открытый в браузере (claude.ai/chat/<uuid>).
            if let url = context.chromeTab?.url, case .claude(let webID)? = ChatLinkParser.parse(url), webID == id {
                return .sameID
            }
            guard KnownBundleIDs.same(context.bundleID, KnownBundleIDs.claude) else { return .none }
            return titleScore(bound: ref.title, current: context.windowTitle)

        case .chatGPTThread(let ref):
            if let current = context.chatGPTThreadID, current == ref.threadID { return .sameID }
            guard KnownBundleIDs.same(context.bundleID, KnownBundleIDs.chatGPT) else { return .none }
            return titleScore(bound: ref.title, current: context.windowTitle)

        case .appWindow(let ref):
            guard KnownBundleIDs.same(context.bundleID, ref.bundleID) else { return .none }
            return titleScore(bound: ref.windowTitle, current: context.windowTitle)
        }
    }

    private static func titleScore(bound: String, current: String?) -> Score {
        let a = TitleCleaner.clean(bound)
        let b = TitleCleaner.clean(current ?? "")
        if !a.isEmpty, a.caseInsensitiveCompare(b) == .orderedSame { return .sameTitle }
        return .sameApp
    }
}
