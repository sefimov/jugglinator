import Foundation

/// One-time copy of user data written by the app under its old name, Juggler
/// (`~/Library/Application Support/Juggler/`, defaults domain `com.sefimov.juggler`),
/// into the Jugglinator locations. Files are copied, not moved, so the old app keeps working.
/// Nothing is overwritten: as soon as the new folder has any of the files, the copy is skipped.
public enum LegacyDataMigration {
    public static let legacyFolderName = "Juggler"
    public static let legacyDefaultsDomain = "com.sefimov.juggler"
    /// Files worth carrying over; `mcp.sock` is recreated by the running app.
    public static let fileNames = ["tasks.json", "tasks.backup.json", "hotkeys.json"]

    public enum FilesOutcome: Equatable, Sendable {
        /// The old folder has none of the files.
        case nothingToDo
        /// The new folder already has at least one of the files; nothing copied.
        case alreadyMigrated
        /// These files were copied.
        case copied([String])
        case failed(String)
    }

    /// `~/Library/Application Support/Juggler/`, next to the new data folder.
    public static func legacyDirectory(for directory: URL) -> URL {
        directory.deletingLastPathComponent().appendingPathComponent(legacyFolderName, isDirectory: true)
    }

    /// Copies `fileNames` from `legacyDirectory` to `directory` when `directory` has none of them yet.
    public static func migrateFiles(
        from legacyDirectory: URL, to directory: URL, fileManager: FileManager = .default
    ) -> FilesOutcome {
        let present = fileNames.filter { fileManager.fileExists(atPath: directory.appendingPathComponent($0).path) }
        if !present.isEmpty { return .alreadyMigrated }
        let available = fileNames.filter { fileManager.fileExists(atPath: legacyDirectory.appendingPathComponent($0).path) }
        if available.isEmpty { return .nothingToDo }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            for name in available {
                try fileManager.copyItem(
                    at: legacyDirectory.appendingPathComponent(name), to: directory.appendingPathComponent(name))
            }
            return .copied(available)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Copies the language choice (`AppleLanguages`) from the old defaults domain when the new domain has none.
    /// Returns `true` when a value was copied.
    public static func migrateLanguage(defaults: UserDefaults, legacyDomain: String, domain: String) -> Bool {
        let key = LanguageSettings.key
        if let current = defaults.persistentDomain(forName: domain)?[key] as? [String], !current.isEmpty { return false }
        guard let legacy = defaults.persistentDomain(forName: legacyDomain)?[key] as? [String], !legacy.isEmpty else { return false }
        var values = defaults.persistentDomain(forName: domain) ?? [:]
        values[key] = legacy
        defaults.setPersistentDomain(values, forName: domain)
        return true
    }

    public struct LaunchOutcome: Equatable, Sendable {
        public var files: FilesOutcome
        public var languageCopied: Bool
    }

    /// The real locations: the data folder of `TaskStore.defaultFileURL` and the app's defaults domain.
    public static func runAtLaunch(fileManager: FileManager = .default) -> LaunchOutcome {
        let directory = TaskStore.defaultFileURL.deletingLastPathComponent()
        let files = migrateFiles(from: legacyDirectory(for: directory), to: directory, fileManager: fileManager)
        let domain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        let language = domain == legacyDefaultsDomain
            ? false
            : migrateLanguage(defaults: .standard, legacyDomain: legacyDefaultsDomain, domain: domain)
        return LaunchOutcome(files: files, languageCopied: language)
    }
}
