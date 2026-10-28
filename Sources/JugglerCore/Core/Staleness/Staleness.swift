import Foundation

/// Уровень «старения» задачи: по нему UI и карточка выбирают цвет.
public enum StalenessLevel: String, Codable, CaseIterable, Sendable {
    /// Ни разу не открывалась.
    case never
    /// Недавно: меньше `aging` минут.
    case fresh
    /// Пора бы вернуться.
    case aging
    /// Давно не был.
    case stale
    /// Похоже, забыта.
    case forgotten
}

/// Пороги уровней в минутах. По умолчанию рассчитаны на сценарий
/// «три задачи по ~3 минуты»: обычный круг укладывается в «свежую» зону.
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
    /// Целые минуты с последнего захода (округление вниз). Время в будущем
    /// (сдвиг часов) считается нулём. `nil` — захода не было.
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

    /// Текст «не был N мин».
    ///
    /// - нет захода → «ещё не был»
    /// - меньше минуты → «был только что»
    /// - до часа → «не был 7 мин»
    /// - до суток → «не был 2 ч» / «не был 1 ч 5 мин»
    /// - дальше → «не был 3 дн»
    public static func absenceText(lastVisited: Date?, now: Date) -> String {
        guard let minutes = minutesSince(lastVisited, now: now) else { return String(localized: "ещё не был") }
        if minutes < 1 { return String(localized: "был только что") }
        if minutes < 60 { return String(localized: "не был \(minutes) мин") }
        if minutes < 24 * 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0 ? String(localized: "не был \(hours) ч") : String(localized: "не был \(hours) ч \(rest) мин")
        }
        return String(localized: "не был \(minutes / (24 * 60)) дн")
    }
}
