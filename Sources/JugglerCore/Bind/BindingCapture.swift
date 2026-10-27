import Foundation

/// Сопоставление заголовков окон: какое окно приложения поднять при активации.
public enum WindowTitleMatcher {
    /// Индекс окна с тем же заголовком: сначала точное совпадение, затем очищенный
    /// (`TitleCleaner`) заголовок без учёта регистра. Пустой искомый заголовок — `nil`.
    public static func bestIndex(of target: String, in titles: [String]) -> Int? {
        let raw = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if let i = titles.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == raw }) {
            return i
        }
        let cleaned = TitleCleaner.clean(raw)
        guard !cleaned.isEmpty else { return nil }
        return titles.firstIndex { TitleCleaner.clean($0).caseInsensitiveCompare(cleaned) == .orderedSame }
    }
}

/// Привязка по контексту переднего окна (без диалогов).
public enum BindingCapture {
    /// - Chrome → вкладка (нужен AppleScript; без него — ошибка с пояснением);
    /// - Claude → чат, если id прочитан, иначе запрос ссылки;
    /// - ChatGPT → тред, если id известен, иначе запрос ссылки `codex://threads/<id>`;
    /// - Grok Bot и прочие → окно (bundle id и заголовок, заголовок может быть пустым без Accessibility).
    public static func capture(
        context: FrontmostContext,
        chromeStatus: AutomationStatus? = nil,
        ownBundleID: String? = BindApps.juggler
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
            return .needsManualLink(.claudeChat, suggestedTitle: title)

        case .chatGPT:
            let title = TitleCleaner.suggestedTaskTitle(from: context.windowTitle)
            if let id = context.chatGPTThreadID, !id.isEmpty {
                return .captured(.chatGPTThread(ChatGPTThreadRef(threadID: id, title: storedTitle(context.windowTitle))), suggestedTitle: title)
            }
            return .needsManualLink(.chatGPTThread, suggestedTitle: title)

        case .other:
            let appName = context.appName ?? ""
            let windowTitle = context.windowTitle ?? ""
            let title = TitleCleaner.suggestedTaskTitle(from: windowTitle, fallback: appName.isEmpty ? "Новая задача" : appName)
            return .captured(.appWindow(AppWindowRef(bundleID: bundleID, windowTitle: windowTitle, appName: appName)), suggestedTitle: title)
        }
    }

    /// Привязка по ссылке, вставленной пользователем.
    ///
    /// Для ChatGPT голый UUID считается id треда (а не чатом Claude, как в `ChatLinkParser`).
    /// Явная ссылка другого источника принимается как есть: `claude.ai/chat/…` в окне ChatGPT — это чат Claude.
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
        case .chatGPT(let id)?:
            return .binding(.chatGPTThread(ChatGPTThreadRef(threadID: id, title: title)))
        case nil:
            return .invalid(BindTexts.unrecognizedLink(expected))
        }
    }

    /// Заголовок, сохраняемый в привязке: исходный заголовок окна без лишних пробелов.
    static func storedTitle(_ title: String?) -> String {
        (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum ManualLinkOutcome: Equatable, Sendable {
    case binding(TaskBinding)
    /// Ссылка не распознана; строка — пояснение на русском.
    case invalid(String)
}

/// Что делать с захваченной привязкой в сценарии «Сделать задачей текущий чат».
public enum BindPlan: Equatable, Sendable {
    /// Этот чат уже привязан к задаче — просто сделать её текущей.
    case alreadyBound(taskID: UUID, number: Int)
    /// У текущей задачи нет привязки — предложить привязать чат к ней.
    case offerAttach(taskID: UUID, number: Int, taskTitle: String)
    /// Создать новую задачу.
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

    /// Указывают ли две привязки на одно и то же (вкладку, чат, тред или окно).
    public static func sameTarget(_ a: TaskBinding, _ b: TaskBinding) -> Bool {
        switch (a, b) {
        case (.chromeTab(let x), .chromeTab(let y)):
            if let i = x.tabID, let j = y.tabID, i == j { return true }
            return !x.url.isEmpty && URLNormalizer.normalize(x.url) == URLNormalizer.normalize(y.url)
        case (.claudeChat(let x), .claudeChat(let y)):
            return x.conversationID.lowercased() == y.conversationID.lowercased()
        case (.chatGPTThread(let x), .chatGPTThread(let y)):
            return x.threadID == y.threadID
        case (.appWindow(let x), .appWindow(let y)):
            guard BindApps.same(x.bundleID, y.bundleID) else { return false }
            let tx = TitleCleaner.clean(x.windowTitle), ty = TitleCleaner.clean(y.windowTitle)
            return tx.caseInsensitiveCompare(ty) == .orderedSame
        default:
            return false
        }
    }

    /// Новая задача с привязкой в конце списка; она же становится текущей. Возвращает её id.
    @discardableResult
    public static func createTask(in document: inout TasksDocument, title: String, binding: TaskBinding, now: Date) -> UUID {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = JugglerTask(title: cleanTitle.isEmpty ? "Новая задача" : cleanTitle, createdAt: now, binding: binding)
        document.tasks.append(task)
        document.markVisited(task.id, at: now)
        return task.id
    }

    /// Привязать к существующей задаче; пустое название заменяется предложенным.
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
