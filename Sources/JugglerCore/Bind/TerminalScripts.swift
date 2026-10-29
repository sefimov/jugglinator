import Foundation

/// AppleScript sources for Terminal.app and parsing of their output.
///
/// As with Chrome (`ChromeScripts`): a single string, fields separated by U+001F, records by U+001E.
/// These characters never occur in ttys or window titles.
public enum TerminalScripts {
    public static let fieldSeparator: Character = ChromeScripts.fieldSeparator
    public static let recordSeparator: Character = ChromeScripts.recordSeparator

    /// Front window and selected tab: `windowID␟tty␟title`; an empty string means no windows.
    /// A window without tabs (a utility one) gives an empty tty.
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

    /// All tabs of all windows: records `windowID␟index␟tty␟title` (title is the window's), separated by U+001E.
    /// ttys are fetched in bulk (`tty of every tab`); a window with anything unreadable is skipped.
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

    /// Raise window `windowID` and, if given, select tab `tabIndex` (1-based).
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

    /// Parses `frontWindowSource` output. `nil` — no windows, unrecognized output, or neither id nor tty.
    public static func parseFrontWindow(_ output: String) -> TerminalWindowRef? {
        let fields = output.split(separator: fieldSeparator, maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 2 else { return nil }
        let title = fields.count > 2 ? fields[2].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let ref = TerminalWindowRef(windowID: ChromeScripts.parseID(fields[0]), tty: fields[1], title: title)
        return ref.hasIdentity ? ref : nil
    }

    /// Parses `tabListingSource` output. Incomplete records are skipped.
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

/// A tab from the list of all Terminal tabs.
public struct TerminalTabEntry: Equatable, Sendable {
    public var windowID: Int
    /// Tab position in the window, 1-based (for `selected tab`).
    public var index: Int
    public var tty: String
    /// Window title (of its selected tab).
    public var windowTitle: String

    public init(windowID: Int, index: Int, tty: String, windowTitle: String = "") {
        self.windowID = windowID
        self.index = index
        self.tty = tty
        self.windowTitle = windowTitle
    }
}

/// Finds the bound tab among open ones: by tty, then by window id, then by window title.
public enum TerminalTabMatcher {
    public enum MatchKind: String, Equatable, Sendable {
        /// The same tab (tty).
        case byTTY
        /// The same window; the tab cannot be found (its tty is unknown or it is closed) — the selected tab is left unchanged.
        case byWindowID
        /// A window with the same title (without size, shell and other noise).
        case byTitle
    }

    public struct Match: Equatable, Sendable {
        public var windowID: Int
        /// Tab to select; `nil` — leave the selection unchanged.
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

/// How well the Terminal window in the context matches the binding (shared logic for
/// `CurrentTaskResolver` and `ExactTaskMatcher`).
public enum TerminalWindowMatch: Int, Comparable, Sendable {
    /// Same window by title without noise — only when the context has neither tty nor window id.
    case title = 1
    /// Same window, and one side's tab tty is unknown.
    case window = 2
    /// The same tab (tty).
    case tab = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// - Returns: `nil` if the frontmost app is not Terminal or it is a different window/tab.
    ///   If both sides know the tty and it differs, it is a different tab, even in the same window.
    public static func evaluate(_ ref: TerminalWindowRef, context: FrontmostContext) -> TerminalWindowMatch? {
        guard KnownBundleIDs.same(context.bundleID, KnownBundleIDs.terminal) else { return nil }
        if let current = context.terminalWindow, current.hasIdentity {
            if !ref.tty.isEmpty, !current.tty.isEmpty {
                return ref.tty == current.tty ? .tab : nil
            }
            if let a = ref.windowID, let b = current.windowID, a == b { return .window }
            return nil
        }
        // No AppleScript access: only the window title (Accessibility) without size and shell is left.
        return TerminalTitle.same(ref.title, context.windowTitle) ? .title : nil
    }

    /// Binding to a Terminal window from the frontmost window context, if the tty or window id was read.
    public static func ref(from context: FrontmostContext) -> TerminalWindowRef? {
        guard KnownBundleIDs.same(context.bundleID, KnownBundleIDs.terminal),
              var ref = context.terminalWindow, ref.hasIdentity else { return nil }
        if ref.title.isEmpty { ref.title = (context.windowTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        return ref
    }
}
