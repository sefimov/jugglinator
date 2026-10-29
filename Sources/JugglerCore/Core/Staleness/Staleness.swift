import Foundation

/// A task's "staleness" level: the UI and the card pick a color by it.
public enum StalenessLevel: String, Codable, CaseIterable, Sendable {
    /// Never opened.
    case never
    /// Recent: less than `aging` minutes.
    case fresh
    /// Time to come back.
    case aging
    /// Away for a long time.
    case stale
    /// Looks forgotten.
    case forgotten
}

/// Level thresholds in minutes. Defaults are tuned for the
/// "three tasks of ~3 minutes each" scenario: a normal cycle stays in the "fresh" zone.
public struct StalenessThresholds: Equatable, Codable, Sendable {
    public var agingMinutes: Int
    public var staleMinutes: Int
    public var forgottenMinutes: Int

    public init(agingMinutes: Int = 10, staleMinutes: Int = 30, forgottenMinutes: Int = 60) {
        self.agingMinutes = agingMinutes
        self.staleMinutes = staleMinutes
        self.forgottenMinutes = forgottenMinutes
    }

    public static let standard = StalenessThresholds()
}

public enum Staleness {
    /// Whole minutes since the last visit (rounded down). A time in the future
    /// (clock shift) counts as zero. `nil` — no visit yet.
    public static func minutesSince(_ lastVisited: Date?, now: Date) -> Int? {
        guard let lastVisited else { return nil }
        let seconds = now.timeIntervalSince(lastVisited)
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(min(seconds / 60, Double(Int.max / 2)).rounded(.down))
    }

    public static func level(
        lastVisited: Date?, now: Date, thresholds: StalenessThresholds = .standard
    ) -> StalenessLevel {
        guard let minutes = minutesSince(lastVisited, now: now) else { return .never }
        if minutes >= thresholds.forgottenMinutes { return .forgotten }
        if minutes >= thresholds.staleMinutes { return .stale }
        if minutes >= thresholds.agingMinutes { return .aging }
        return .fresh
    }

    /// The "away N min" text.
    ///
    /// - no visit → "not visited yet"
    /// - under a minute → "just visited"
    /// - under an hour → "away 7 min"
    /// - under a day → "away 2 h" / "away 1 h 5 min"
    /// - longer → "away 3 d"
    public static func absenceText(lastVisited: Date?, now: Date) -> String {
        guard let minutes = minutesSince(lastVisited, now: now) else { return loc("ещё не был") }
        if minutes < 1 { return loc("был только что") }
        if minutes < 60 { return loc("не был \(minutes) мин") }
        if minutes < 24 * 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0 ? loc("не был \(hours) ч") : loc("не был \(hours) ч \(rest) мин")
        }
        return loc("не был \(minutes / (24 * 60)) дн")
    }
}
