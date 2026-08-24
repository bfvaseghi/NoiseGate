import Foundation

/// Constants shared by every target (apps, extensions, widgets).
enum AppGroup {
    /// ⚠️ Change this to your own app-group identifier and keep it in sync with
    /// the `com.apple.security.application-groups` entries in project.yml.
    static let id = "group.com.example.noisegate"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }
}

enum StoreKey {
    static let budgetConfig = "budgetConfig"        // BudgetConfig JSON
    static let usageSnapshot = "usageSnapshot"      // UsageSnapshot JSON (widget feed)
    static let noiseSelection = "noiseSelection"    // FamilyActivitySelection JSON (iOS)
    static let messagesSelection = "messagesSelection"
    static let mutedNoise = "mutedNoise"            // MutedTokens JSON (iOS) — paused noise apps
    static let mutedMessages = "mutedMessages"      // MutedTokens JSON (iOS)
    static let macNoiseApps = "macNoiseApps"        // [String] bundle ids (macOS)
    static let macMessagesApps = "macMessagesApps"  // [String] bundle ids (macOS)
    static let macLedger = "macLedger"              // MacLedger JSON (macOS)
    static let macNudgesSent = "macNudgesSent"      // [String] nudge ids sent today (macOS)
}

enum DayKey {
    /// Local-timezone day key, e.g. "2026-08-24". Everything resets when it changes.
    static func today(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

extension UserDefaults {
    func codable<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func setCodable<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            set(data, forKey: key)
        }
    }
}
