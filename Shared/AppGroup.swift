import Foundation

/// Constants shared by every target (apps, extensions, widgets).
enum AppGroup {
    /// Configure this and every entitlement together with
    /// `Scripts/configure_signing.py`. Never edit one target in isolation.
    static let id = "group.com.example.noisegate"

    /// Resolved once per process. `UserDefaults` is thread-safe, and this is
    /// read from view bodies and five-second tracker ticks, so re-running the
    /// suite lookup every access is pure waste.
    static let defaults: UserDefaults = UserDefaults(suiteName: id) ?? .standard

    /// Also resolved once: `containerURL(forSecurityApplicationGroupIdentifier:)`
    /// hits the filesystem, and `SharedStore` asks for it on every locked write.
    static let containerURL: URL? = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: id
    )
}

enum StoreKey {
    static let budgetConfig = "budgetConfig"        // BudgetConfig JSON
    static let usageSnapshot = "usageSnapshot"      // UsageSnapshot JSON (widget feed)
    // Raw keys stay unchanged so upgrades preserve Claude's original data.
    static let distractionSelection = "noiseSelection" // FamilyActivitySelection JSON (iOS)
    static let messagesSelection = "messagesSelection"
    static let pausedDistractions = "mutedNoise"    // PausedTokens JSON (iOS)
    static let pausedMessages = "mutedMessages"     // PausedTokens JSON (iOS)
    static let selectionMigrationNoticePending = "selectionMigrationNoticePending.v2"
    static let iosNudgesSent = "iosNudgesSent"      // [String] nudge ids sent today (iOS)
    static let monitoringNeedsReconfigure = "monitoringNeedsReconfigure.v2"
    static let monitoringAcceptsCallbacks = "monitoringAcceptsCallbacks.v2"
    static let monitoringSchemaVersion = "monitoringSchemaVersion"
    static let monitoringGeneration = "monitoringGeneration.v2"
    static let monitoringConfiguredAt = "monitoringConfiguredAt.v2"
    static let usageHistory = "usageHistory"        // [DayRecord] JSON — finished days
    static let accentTheme = "accentTheme"          // AccentTheme rawValue
    static let macDistractionApps = "macNoiseApps"  // [String] bundle ids (macOS)
    static let macMessagesApps = "macMessagesApps"  // [String] bundle ids (macOS)
    static let macSelections = "macSelections.v2"   // MacSelections JSON (macOS)
    static let macLedger = "macLedger"              // MacLedger JSON (macOS)
    static let macNudgesSent = "macNudgesSent"      // [String] nudge ids sent today (macOS)
}

enum DayKey {
    /// Local-timezone day key, e.g. "2026-08-24". Everything resets when it changes.
    static func today(_ date: Date = Date()) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            return "1970-01-01"
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Inverse of `today(_:)` — midnight local time for a stored day key.
    static func date(from dayKey: String) -> Date? {
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// A fresh calendar observes timezone changes while the app is running.
    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .autoupdatingCurrent
        return value
    }
}
