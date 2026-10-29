import Foundation

/// Determines the current task from the frontmost window context.
///
/// Each binding gets a match score against the context; the highest wins.
/// On a tie, `fallbackID` (the last active task) wins if it is among
/// the best, otherwise the first in list order. The "done" mark does not prevent a match:
/// skipping done tasks is `TaskCycler`'s job.
public enum CurrentTaskResolver {
    /// Match strength. Values are ordered: an exact id beats a URL, a URL beats a title.
    public enum Score: Int, Comparable, Sendable {
        case none = 0
        /// Same app, title did not match or is unknown.
        case sameApp = 20
        /// Same app and same cleaned window title.
        case sameTitle = 50
        /// Same tab URL (ignoring fragment, host case and trailing "/").
        case sameURL = 80
        /// Same id: Chrome tab, Claude chat, Claude Code session, ChatGPT thread or Terminal tab tty.
        /// For Terminal, "same window" (window id, tty unknown) is `sameURL`.
        case sameID = 100

        public static func < (lhs: Score, rhs: Score) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The task matching the frontmost window; if nothing matches — `fallbackID`
    /// (if such a task is in the list), otherwise `nil`.
    public static func resolve(context: FrontmostContext, tasks: [JugglerTask], fallbackID: UUID? = nil) -> UUID? {
        if let matched = match(context: context, tasks: tasks, fallbackID: fallbackID) {
            return matched
        }
        guard let fallbackID, tasks.contains(where: { $0.id == fallbackID }) else { return nil }
        return fallbackID
    }

    /// Context match only, without the fallback.
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
            // The same chat opened in the browser (claude.ai/chat/<uuid>).
            if let url = context.chromeTab?.url, case .claude(let webID)? = ChatLinkParser.parse(url), webID == id {
                return .sameID
            }
            guard KnownBundleIDs.same(context.bundleID, KnownBundleIDs.claude) else { return .none }
            return titleScore(bound: ref.title, current: context.windowTitle)

        case .claudeCodeSession(let ref):
            let id = ref.sessionID.lowercased()
            if let current = context.claudeCodeSessionID?.lowercased(), current == id { return .sameID }
            guard KnownBundleIDs.same(context.bundleID, KnownBundleIDs.claude) else { return .none }
            // The Code tab window title is just "Claude", so this is usually only "same app".
            return titleScore(bound: ref.title, current: context.windowTitle)

        case .chatGPTThread(let ref):
            if let current = context.chatGPTThreadID, current == ref.threadID { return .sameID }
            guard KnownBundleIDs.isChatGPT(context.bundleID) else { return .none }
            return titleScore(bound: ref.title, current: context.windowTitle)

        case .terminalWindow(let ref):
            guard KnownBundleIDs.same(context.bundleID, KnownBundleIDs.terminal) else { return .none }
            switch TerminalWindowMatch.evaluate(ref, context: context) {
            case .tab?: return .sameID
            case .window?: return .sameURL
            case .title?: return .sameTitle
            case nil: return .sameApp
            }

        case .appWindow(let ref):
            guard KnownBundleIDs.same(context.bundleID, ref.bundleID) else { return .none }
            if KnownBundleIDs.same(ref.bundleID, KnownBundleIDs.terminal) {
                // Terminal window without AppleScript: title without size and shell.
                return TerminalTitle.same(ref.windowTitle, context.windowTitle) ? .sameTitle : .sameApp
            }
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
