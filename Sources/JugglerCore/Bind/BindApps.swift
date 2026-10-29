import Foundation

// The Sources/JugglerCore/Bind/ folder belongs to the BIND task: pure logic (Foundation only)
// checked by JugglerChecks (Sources/JugglerChecks/Bind/).

/// Which apps BIND distinguishes when binding and activating.
public enum BindAppKind: String, Codable, Equatable, Sendable {
    case chrome
    case claude
    case chatGPT
    /// Terminal.app: window and tab (window id, tty).
    case terminal
    /// Grok Bot and any other app: window binding.
    case other
}

/// App bundle ids, verified on the user's Mac (Info.plist in /Applications).
///
/// ChatGPT desktop currently ships as `com.openai.codex` (scheme `codex`);
/// the old `com.openai.chat` is kept for compatibility.
public enum BindApps {
    public static let chrome = KnownBundleIDs.chrome
    public static let claude = KnownBundleIDs.claude
    public static let chatGPTBundleIDs = KnownBundleIDs.chatGPTAll
    public static let grokBot = KnownBundleIDs.grokBot
    public static let terminal = KnownBundleIDs.terminal
    public static let juggler = "com.sefimov.juggler"

    public static func kind(of bundleID: String?) -> BindAppKind {
        guard let bundleID, !bundleID.isEmpty else { return .other }
        if same(bundleID, chrome) { return .chrome }
        if same(bundleID, claude) { return .claude }
        if chatGPTBundleIDs.contains(where: { same(bundleID, $0) }) { return .chatGPT }
        if same(bundleID, terminal) { return .terminal }
        return .other
    }

    public static func isChatGPT(_ bundleID: String?) -> Bool { kind(of: bundleID) == .chatGPT }

    /// Case-insensitive bundle id comparison; empty and `nil` equal nothing.
    public static func same(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b, !a.isEmpty, !b.isEmpty else { return false }
        return a.caseInsensitiveCompare(b) == .orderedSame
    }
}

/// A candidate "frontmost" app (for choosing whose window to bind).
public struct AppIdentity: Codable, Equatable, Sendable {
    public var bundleID: String?
    public var name: String?
    public var pid: Int32

    public init(bundleID: String?, name: String?, pid: Int32) {
        self.bundleID = bundleID
        self.name = name
        self.pid = pid
    }
}

/// Chooses the app whose context to read.
///
/// When "Make the current chat a task" is clicked in the Juggler menu, Juggler itself
/// may be frontmost. Then the last active app other than Juggler is used.
public enum FrontmostAppChooser {
    public static func isOwn(_ app: AppIdentity, ownBundleID: String?, ownPID: Int32) -> Bool {
        if app.pid == ownPID { return true }
        if BindApps.same(app.bundleID, ownBundleID) { return true }
        return BindApps.same(app.bundleID, BindApps.juggler)
    }

    /// - Returns: the app and a flag saying the remembered one was used rather than the current frontmost.
    public static func choose(
        frontmost: AppIdentity?, remembered: AppIdentity?, ownBundleID: String?, ownPID: Int32
    ) -> (app: AppIdentity, usedRemembered: Bool)? {
        if let frontmost, !isOwn(frontmost, ownBundleID: ownBundleID, ownPID: ownPID) {
            return (frontmost, false)
        }
        if let remembered, !isOwn(remembered, ownBundleID: ownBundleID, ownPID: ownPID) {
            return (remembered, true)
        }
        return nil
    }
}
