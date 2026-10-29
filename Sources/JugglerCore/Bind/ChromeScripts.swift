import Foundation

/// AppleScript sources for Chrome and parsing of their output.
///
/// Scripts return a single string: fields separated by U+001F (unit separator),
/// records by U+001E (record separator). These characters never occur in tab URLs and titles,
/// so parsing is unambiguous and can be checked without Chrome.
public enum ChromeScripts {
    public static let fieldSeparator: Character = "\u{1F}"
    public static let recordSeparator: Character = "\u{1E}"

    /// Active tab of the front window: `windowID␟tabID␟URL␟title`; an empty string means no windows.
    public static func activeTabSource(bundleID: String = BindApps.chrome) -> String {
        """
        with timeout of 3 seconds
        tell application id "\(bundleID)"
            if (count of windows) is 0 then return ""
            set sep to character id 31
            set w to front window
            set t to active tab of w
            return ((id of w) as text) & sep & ((id of t) as text) & sep & (URL of t) & sep & (title of t)
        end tell
        end timeout
        """
    }

    /// All tabs of all windows: records `windowID␟index␟tabID␟URL`, separated by U+001E.
    /// Properties are fetched in bulk (`id of every tab`) to avoid sending an event per tab.
    public static func tabListingSource(bundleID: String = BindApps.chrome) -> String {
        """
        with timeout of 5 seconds
        tell application id "\(bundleID)"
            set sep to character id 31
            set nl to character id 30
            set out to ""
            repeat with w in windows
                set wid to (id of w) as text
                set ids to id of every tab of w
                set urls to URL of every tab of w
                repeat with i from 1 to count of ids
                    set out to out & wid & sep & (i as text) & sep & ((item i of ids) as text) & sep & (item i of urls) & nl
                end repeat
            end repeat
            return out
        end tell
        end timeout
        """
    }

    /// Make tab `tabIndex` (1-based) active in window `windowID` and raise the window.
    public static func focusTabSource(windowID: Int, tabIndex: Int, bundleID: String = BindApps.chrome) -> String {
        """
        with timeout of 3 seconds
        tell application id "\(bundleID)"
            set w to window id \(windowID)
            try
                if minimized of w then set minimized of w to false
            end try
            set active tab index of w to \(tabIndex)
            set index of w to 1
            activate
        end tell
        end timeout
        """
    }

    /// Parses `activeTabSource` output. `nil` — no windows or unrecognized output.
    public static func parseActiveTab(_ output: String) -> ChromeTabRef? {
        let fields = output.split(separator: fieldSeparator, maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 3 else { return nil }
        let url = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }
        let title = fields.count > 3 ? fields[3].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return ChromeTabRef(tabID: parseID(fields[1]), windowID: parseID(fields[0]), url: url, title: title)
    }

    /// Parses `tabListingSource` output. Incomplete records are skipped.
    public static func parseTabListing(_ output: String) -> [ChromeTabEntry] {
        output.split(separator: recordSeparator).compactMap { record in
            let fields = record.split(separator: fieldSeparator, maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 4,
                  let windowID = parseID(fields[0]),
                  let index = parseID(fields[1]), index >= 1 else { return nil }
            return ChromeTabEntry(
                windowID: windowID, index: index, tabID: parseID(fields[2]),
                url: fields[3].trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// An integer from AppleScript text: "123", "123.0" (AppleScript sometimes prints a real like that), with whitespace.
    public static func parseID(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let v = Int(t) { return v }
        if let d = Double(t), d.rounded() == d, abs(d) < 9.0e15 { return Int(d) }
        return nil
    }
}

/// A tab from the list of all Chrome tabs.
public struct ChromeTabEntry: Equatable, Sendable {
    public var windowID: Int
    /// Tab position in the window, 1-based (for `active tab index`).
    public var index: Int
    public var tabID: Int?
    public var url: String

    public init(windowID: Int, index: Int, tabID: Int?, url: String) {
        self.windowID = windowID
        self.index = index
        self.tabID = tabID
        self.url = url
    }
}

/// Finds the bound tab among open ones: first by id, then by URL.
public enum ChromeTabMatcher {
    public enum MatchKind: String, Equatable, Sendable {
        case byID
        case byURL
    }

    public struct Match: Equatable, Sendable {
        public var entry: ChromeTabEntry
        public var kind: MatchKind
    }

    /// URL comparison goes through `URLNormalizer` (host case, `#fragment`, trailing `/`).
    /// Among several tabs with the same URL, the binding's window is preferred, then the first one.
    public static func find(_ ref: ChromeTabRef, in entries: [ChromeTabEntry]) -> Match? {
        if let id = ref.tabID, let entry = entries.first(where: { $0.tabID == id }) {
            return Match(entry: entry, kind: .byID)
        }
        let target = URLNormalizer.normalize(ref.url)
        guard !target.isEmpty else { return nil }
        let same = entries.filter { URLNormalizer.normalize($0.url) == target }
        if let windowID = ref.windowID, let entry = same.first(where: { $0.windowID == windowID }) {
            return Match(entry: entry, kind: .byURL)
        }
        return same.first.map { Match(entry: $0, kind: .byURL) }
    }

    /// A URL that can be reopened if the tab is gone.
    public static func reopenURL(for ref: ChromeTabRef) -> URL? {
        let text = ref.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              ["http", "https", "file"].contains(scheme) else { return nil }
        return url
    }
}
