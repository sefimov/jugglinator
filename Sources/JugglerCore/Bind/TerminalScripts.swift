import Foundation

/// Тексты AppleScript для Terminal.app и разбор их вывода.
///
/// Как и у Chrome (`ChromeScripts`): одна строка, поля разделены U+001F, записи — U+001E.
/// В tty и заголовках окон эти символы не встречаются.
public enum TerminalScripts {
    public static let fieldSeparator: Character = ChromeScripts.fieldSeparator
    public static let recordSeparator: Character = ChromeScripts.recordSeparator

    /// Переднее окно и выбранная вкладка: `windowID␟tty␟title`; пустая строка — окон нет.
    /// Окно без вкладок (служебное) даёт пустой tty.
    public static func frontWindowSource(bundleID: String = BindApps.terminal) -> String {
        """
        with timeout of 3 seconds
        tell application id "\(bundleID)"
            if (count of windows) is 0 then return ""
            set sep to character id 31
            set w to front window
            set t to ""
            try
                set t to tty of selected tab of w
            end try
            return ((id of w) as text) & sep & t & sep & (name of w)
        end tell
        end timeout
        """
    }

    /// Все вкладки всех окон: записи `windowID␟index␟tty␟title` (заголовок — окна), разделённые U+001E.
    /// tty берутся пачкой (`tty of every tab`); окно, у которого что-то не читается, пропускается.
    public static func tabListingSource(bundleID: String = BindApps.terminal) -> String {
        """
        with timeout of 5 seconds
        tell application id "\(bundleID)"
            set sep to character id 31
            set nl to character id 30
            set out to ""
            repeat with w in windows
                try
                    set wid to (id of w) as text
                    set wname to name of w
                    set ttys to tty of every tab of w
                    repeat with i from 1 to count of ttys
                        set out to out & wid & sep & (i as text) & sep & (item i of ttys) & sep & wname & nl
                    end repeat
                end try
            end repeat
            return out
        end tell
        end timeout
        """
    }

    /// Поднять окно `windowID` и, если задано, выбрать вкладку `tabIndex` (с 1).
    public static func focusSource(windowID: Int, tabIndex: Int?, bundleID: String = BindApps.terminal) -> String {
        let selectTab = tabIndex.map { "set selected tab of w to tab \($0) of w" } ?? ""
        return """
        with timeout of 3 seconds
        tell application id "\(bundleID)"
            set w to window id \(windowID)
            try
                if miniaturized of w then set miniaturized of w to false
            end try
            \(selectTab)
            set index of w to 1
            try
                set frontmost of w to true
            end try
            activate
        end tell
        end timeout
        """
    }

    /// Разбор вывода `frontWindowSource`. `nil` — окон нет, вывод не распознан или нет ни id, ни tty.
    public static func parseFrontWindow(_ output: String) -> TerminalWindowRef? {
        let fields = output.split(separator: fieldSeparator, maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 2 else { return nil }
        let title = fields.count > 2 ? fields[2].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let ref = TerminalWindowRef(windowID: ChromeScripts.parseID(fields[0]), tty: fields[1], title: title)
        return ref.hasIdentity ? ref : nil
    }

    /// Разбор вывода `tabListingSource`. Неполные записи пропускаются.
    public static func parseTabListing(_ output: String) -> [TerminalTabEntry] {
        output.split(separator: recordSeparator).compactMap { record in
            let fields = record.split(separator: fieldSeparator, maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3,
                  let windowID = ChromeScripts.parseID(fields[0]),
                  let index = ChromeScripts.parseID(fields[1]), index >= 1 else { return nil }
            return TerminalTabEntry(
                windowID: windowID, index: index,
                tty: fields[2].trimmingCharacters(in: .whitespacesAndNewlines),
                windowTitle: fields.count > 3 ? fields[3].trimmingCharacters(in: .whitespacesAndNewlines) : "")
        }
    }
}

/// Вкладка из списка всех вкладок Терминала.
public struct TerminalTabEntry: Equatable, Sendable {
    public var windowID: Int
    /// Позиция вкладки в окне, с 1 (для `selected tab`).
    public var index: Int
    public var tty: String
    /// Заголовок окна (выбранной в нём вкладки).
    public var windowTitle: String

    public init(windowID: Int, index: Int, tty: String, windowTitle: String = "") {
        self.windowID = windowID
        self.index = index
        self.tty = tty
        self.windowTitle = windowTitle
    }
}

/// Поиск привязанной вкладки среди открытых: по tty, затем по id окна, затем по заголовку окна.
public enum TerminalTabMatcher {
    public enum MatchKind: String, Equatable, Sendable {
        /// Та же вкладка (tty).
        case byTTY
        /// То же окно; вкладку не найти (её tty не известен или она закрыта) — выбранная вкладка не меняется.
        case byWindowID
        /// Окно с тем же заголовком (без размера, оболочки и прочего шума).
        case byTitle
    }

    public struct Match: Equatable, Sendable {
        public var windowID: Int
        /// Вкладка, которую выбрать; `nil` — не менять выбранную.
        public var tabIndex: Int?
        public var kind: MatchKind

        public init(windowID: Int, tabIndex: Int?, kind: MatchKind) {
            self.windowID = windowID
            self.tabIndex = tabIndex
            self.kind = kind
        }
    }

    public static func find(_ ref: TerminalWindowRef, in entries: [TerminalTabEntry]) -> Match? {
        if !ref.tty.isEmpty, let entry = entries.first(where: { $0.tty == ref.tty }) {
            return Match(windowID: entry.windowID, tabIndex: entry.index, kind: .byTTY)
        }
        if let id = ref.windowID, entries.contains(where: { $0.windowID == id }) {
            return Match(windowID: id, tabIndex: nil, kind: .byWindowID)
        }
        if let entry = entries.first(where: { TerminalTitle.same(ref.title, $0.windowTitle) }) {
            return Match(windowID: entry.windowID, tabIndex: nil, kind: .byTitle)
        }
        return nil
    }
}

/// Насколько окно Терминала в контексте совпадает с привязкой (общая логика для
/// `CurrentTaskResolver` и `ExactTaskMatcher`).
public enum TerminalWindowMatch: Int, Comparable, Sendable {
    /// То же окно по заголовку без шума — только когда в контексте нет ни tty, ни id окна.
    case title = 1
    /// То же окно, а tty вкладки у одной из сторон не известен.
    case window = 2
    /// Та же вкладка (tty).
    case tab = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// - Returns: `nil`, если впереди не Терминал или это другое окно/вкладка.
    ///   Если обе стороны знают tty и он разный — это другая вкладка, даже в том же окне.
    public static func evaluate(_ ref: TerminalWindowRef, context: FrontmostContext) -> TerminalWindowMatch? {
        guard KnownBundleIDs.same(context.bundleID, KnownBundleIDs.terminal) else { return nil }
        if let current = context.terminalWindow, current.hasIdentity {
            if !ref.tty.isEmpty, !current.tty.isEmpty {
                return ref.tty == current.tty ? .tab : nil
            }
            if let a = ref.windowID, let b = current.windowID, a == b { return .window }
            return nil
        }
        // Нет доступа к AppleScript: остаётся заголовок окна (Accessibility) без размера и оболочки.
        return TerminalTitle.same(ref.title, context.windowTitle) ? .title : nil
    }

    /// Привязка к окну Терминала из контекста переднего окна, если tty или id окна прочитаны.
    public static func ref(from context: FrontmostContext) -> TerminalWindowRef? {
        guard KnownBundleIDs.same(context.bundleID, KnownBundleIDs.terminal),
              var ref = context.terminalWindow, ref.hasIdentity else { return nil }
        if ref.title.isEmpty { ref.title = (context.windowTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        return ref
    }
}
