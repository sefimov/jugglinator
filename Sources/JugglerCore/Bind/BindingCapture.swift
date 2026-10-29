import Foundation

/// Window title matching: which app window to raise on activation.
public enum WindowTitleMatcher {
    /// Index of the window with the same title: exact match first, then the cleaned
    /// (`TitleCleaner`) title, case-insensitive. An empty search title gives `nil`.
    ///
    /// For Terminal (`bundleID`), after the exact match, titles are compared without size,
    /// shell and other noise (`TerminalTitle`).
    public static func bestIndex(of target: String, in titles: [String], bundleID: String? = nil) -> Int? {
        let raw = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if let i = titles.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == raw }) {
            return i
        }
        if KnownBundleIDs.same(bundleID, KnownBundleIDs.terminal) {
            return titles.firstIndex { TerminalTitle.same(raw, $0) }
        }
        let cleaned = TitleCleaner.clean(raw)
        guard !cleaned.isEmpty else { return nil }
        return titles.firstIndex { TitleCleaner.clean($0).caseInsensitiveCompare(cleaned) == .orderedSame }
    }
}

/// Binding from the frontmost window context (no dialogs).
public enum BindingCapture {
    /// - Chrome → tab (requires AppleScript; without it — an error with an explanation);
    /// - Claude → chat if the id was read; Claude Code session (Code tab) if its id was read
    ///   (title from session metadata, otherwise from the window title); otherwise a link request;
    /// - ChatGPT → thread if the id is known or the thread is unambiguously found by window title
    ///   in `~/.codex/session_index.jsonl` (`chatGPTLookup`; title from the thread), otherwise a `codex://threads/<id>` link request;
    /// - Terminal → window and tab (window id and tty from AppleScript); without permission — a plain window;
    ///   title from the window title without size, shell and other noise (`TerminalTitle`);
    /// - Grok Bot and others → window (bundle id and title; the title may be empty without Accessibility).
    public static func capture(
        context: FrontmostContext,
        chromeStatus: AutomationStatus? = nil,
        ownBundleID: String? = BindApps.juggler,
        chatGPTLookup: ChatGPTThreadLookup? = nil
    ) -> BindingCaptureResult {
        guard let bundleID = context.bundleID, !bundleID.isEmpty else {
            return .failed(BindTexts.noFrontmostApp)
        }
        if BindApps.same(bundleID, ownBundleID) || BindApps.same(bundleID, BindApps.juggler) {
            return .failed(BindTexts.frontmostIsJuggler)
        }
        switch BindApps.kind(of: bundleID) {
        case .chrome:
            guard let tab = context.chromeTab else {
                return .failed(BindTexts.chromeTabUnavailable(chromeStatus))
            }
            let title = TitleCleaner.suggestedTaskTitle(from: tab.title.isEmpty ? context.windowTitle : tab.title)
            return .captured(.chromeTab(tab), suggestedTitle: title)

        case .claude:
            let title = TitleCleaner.suggestedTaskTitle(from: context.windowTitle)
            if let id = context.claudeConversationID, ChatLinkParser.isUUID(id) {
                return .captured(.claudeChat(ClaudeChatRef(conversationID: id, title: storedTitle(context.windowTitle))), suggestedTitle: title)
            }
            if let id = context.claudeCodeSessionID, ChatLinkParser.isClaudeCodeSessionID(id) {
                let sessionTitle = storedTitle(context.claudeCodeSessionTitle)
                let suggested = TitleCleaner.suggestedTaskTitle(
                    from: sessionTitle.isEmpty ? context.windowTitle : sessionTitle, fallback: BindTexts.defaultSessionTaskTitle)
                // The Code tab window title is usually just "Claude": stored cleaned to avoid "Claude Code: Claude".
                let ref = ClaudeCodeSessionRef(sessionID: id, title: sessionTitle.isEmpty ? TitleCleaner.clean(context.windowTitle ?? "") : sessionTitle)
                return .captured(.claudeCodeSession(ref), suggestedTitle: suggested)
            }
            return .needsManualLink(.claudeChat, suggestedTitle: title)

        case .chatGPT:
            let title = TitleCleaner.suggestedTaskTitle(from: context.windowTitle)
            if let id = context.chatGPTThreadID, !id.isEmpty {
                return .captured(.chatGPTThread(ChatGPTThreadRef(threadID: id, title: storedTitle(context.windowTitle))), suggestedTitle: title)
            }
            if let lookup = chatGPTLookup, lookup.applies(toWindowTitle: context.windowTitle), let thread = lookup.uniqueMatch {
                // The binding keeps the window title, as with a manual link: it is how the current task is recognized when switching.
                let ref = ChatGPTThreadRef(threadID: thread.id, title: storedTitle(context.windowTitle))
                return .captured(.chatGPTThread(ref), suggestedTitle: TitleCleaner.suggestedTaskTitle(from: thread.name, fallback: title))
            }
            return .needsManualLink(.chatGPTThread, suggestedTitle: title)

        case .terminal:
            if let ref = TerminalWindowMatch.ref(from: context) {
                return .captured(.terminalWindow(ref), suggestedTitle: TerminalTitle.taskTitle(from: ref.title))
            }
            let windowTitle = context.windowTitle ?? ""
            return .captured(.appWindow(AppWindowRef(bundleID: bundleID, windowTitle: windowTitle, appName: context.appName ?? "")),
                             suggestedTitle: TerminalTitle.taskTitle(from: windowTitle))

        case .other:
            let appName = context.appName ?? ""
            let windowTitle = context.windowTitle ?? ""
            let title = TitleCleaner.suggestedTaskTitle(from: windowTitle, fallback: appName.isEmpty ? loc("Новая задача") : appName)
            return .captured(.appWindow(AppWindowRef(bundleID: bundleID, windowTitle: windowTitle, appName: appName)), suggestedTitle: title)
        }
    }

    /// Binding from a link pasted by the user.
    ///
    /// For ChatGPT a bare UUID is treated as a thread id (not a Claude chat, as in `ChatLinkParser`).
    /// An explicit link to another source is accepted as is: `claude.ai/chat/…` in a ChatGPT window is a Claude chat,
    /// `local_<uuid>` and `claude.ai/epitaxy/local_<uuid>` are a Claude Code session.
    /// A "Share" link (`claude.ai/share/…`) is recognized and rejected with an explanation.
    public static func bindingFromManualLink(_ text: String, expected: BindingSource, windowTitle: String?) -> ManualLinkOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalid(BindTexts.emptyLink) }
        let title = storedTitle(windowTitle)
        if expected == .chatGPTThread, ChatLinkParser.isUUID(trimmed) {
            return .binding(.chatGPTThread(ChatGPTThreadRef(threadID: trimmed, title: title)))
        }
        switch ChatLinkParser.parse(trimmed) {
        case .claude(let id)?:
            return .binding(.claudeChat(ClaudeChatRef(conversationID: id, title: title)))
        case .claudeCodeSession(let id)?:
            return .binding(.claudeCodeSession(ClaudeCodeSessionRef(sessionID: id, title: title)))
        case .chatGPT(let id)?:
            return .binding(.chatGPTThread(ChatGPTThreadRef(threadID: id, title: title)))
        case nil:
            if ChatLinkParser.isClaudeShareLink(trimmed) { return .invalid(BindTexts.shareLinkNotSupported) }
            return .invalid(BindTexts.unrecognizedLink(expected))
        }
    }

    /// Link prefilled in the ChatGPT link dialog: with several threads named like the window —
    /// the most recently updated one. Otherwise `nil` (then the clipboard link is used, if suitable).
    public static func chatGPTPrefillLink(lookup: ChatGPTThreadLookup?, windowTitle: String?) -> String? {
        guard let lookup, lookup.applies(toWindowTitle: windowTitle) else { return nil }
        return lookup.prefillLink
    }

    /// Title stored in the binding: the original window title without extra whitespace.
    static func storedTitle(_ title: String?) -> String {
        (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum ManualLinkOutcome: Equatable, Sendable {
    case binding(TaskBinding)
    /// The link was not recognized; the string is a localized explanation.
    case invalid(String)
}

/// What to do with a captured binding in the "Make the current chat a task" flow.
public enum BindPlan: Equatable, Sendable {
    /// This chat is already bound to a task — just make it current.
    case alreadyBound(taskID: UUID, number: Int)
    /// The current task has no binding — offer to bind the chat to it.
    case offerAttach(taskID: UUID, number: Int, taskTitle: String)
    /// Create a new task.
    case createNew
}

public enum BindPlanner {
    public static func plan(document: TasksDocument, binding: TaskBinding) -> BindPlan {
        if let task = document.tasks.first(where: { $0.binding.map { sameTarget($0, binding) } ?? false }),
           let number = document.number(of: task.id) {
            return .alreadyBound(taskID: task.id, number: number)
        }
        if let current = document.lastActiveTask, current.binding == nil, let number = document.number(of: current.id) {
            return .offerAttach(taskID: current.id, number: number, taskTitle: current.title)
        }
        return .createNew
    }

    /// Whether two bindings point to the same thing (tab, chat, thread or window).
    public static func sameTarget(_ a: TaskBinding, _ b: TaskBinding) -> Bool {
        switch (a, b) {
        case (.chromeTab(let x), .chromeTab(let y)):
            if let i = x.tabID, let j = y.tabID, i == j { return true }
            return !x.url.isEmpty && URLNormalizer.normalize(x.url) == URLNormalizer.normalize(y.url)
        case (.claudeChat(let x), .claudeChat(let y)):
            return x.conversationID.lowercased() == y.conversationID.lowercased()
        case (.claudeCodeSession(let x), .claudeCodeSession(let y)):
            return x.sessionID.lowercased() == y.sessionID.lowercased()
        case (.chatGPTThread(let x), .chatGPTThread(let y)):
            return x.threadID == y.threadID
        case (.terminalWindow(let x), .terminalWindow(let y)):
            if !x.tty.isEmpty, !y.tty.isEmpty { return x.tty == y.tty }
            if let i = x.windowID, let j = y.windowID { return i == j }
            return false
        case (.appWindow(let x), .appWindow(let y)):
            guard BindApps.same(x.bundleID, y.bundleID) else { return false }
            let terminal = BindApps.same(x.bundleID, BindApps.terminal)
            let tx = terminal ? TerminalTitle.clean(x.windowTitle) : TitleCleaner.clean(x.windowTitle)
            let ty = terminal ? TerminalTitle.clean(y.windowTitle) : TitleCleaner.clean(y.windowTitle)
            return tx.caseInsensitiveCompare(ty) == .orderedSame
        default:
            return false
        }
    }

    /// A new task with a binding at the end of the list; it also becomes current. Returns its id.
    @discardableResult
    public static func createTask(in document: inout TasksDocument, title: String, binding: TaskBinding, now: Date) -> UUID {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = JugglerTask(title: cleanTitle.isEmpty ? loc("Новая задача") : cleanTitle, createdAt: now, binding: binding)
        document.tasks.append(task)
        document.markVisited(task.id, at: now)
        return task.id
    }

    /// Bind to an existing task; an empty title is replaced with the suggested one.
    @discardableResult
    public static func attach(_ binding: TaskBinding, to id: UUID, in document: inout TasksDocument, suggestedTitle: String, now: Date) -> Bool {
        guard let i = document.index(of: id) else { return false }
        document.tasks[i].binding = binding
        if document.tasks[i].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            document.tasks[i].title = suggestedTitle
        }
        document.markVisited(id, at: now)
        return true
    }
}
