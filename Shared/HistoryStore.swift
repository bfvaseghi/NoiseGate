import Foundation

/// One finished day of usage. On iOS the minutes are threshold floors
/// (`isFloor == true`); on macOS they are exact tracker totals. Records are
/// per-device — iPhone/iPad and Mac each keep their own app-group store.
struct DayRecord: Codable, Equatable, Identifiable {
    let dayKey: String
    var noiseMinutes: Int
    var messagesMinutes: Int
    var noiseBudgetMinutes: Int
    var messagesBudgetMinutes: Int
    var isFloor: Bool

    var id: String { dayKey }
    var date: Date { DayKey.date(from: dayKey) ?? .distantPast }
    var noiseReachedBudget: Bool {
        noiseBudgetMinutes > 0 && noiseMinutes >= noiseBudgetMinutes
    }
    var messagesReachedBudget: Bool {
        messagesBudgetMinutes > 0 && messagesMinutes >= messagesBudgetMinutes
    }
}

/// Rolling per-day history, written at the daily rollover (iOS monitor
/// extension / macOS tracker) and read by the stats card and Mac chart.
enum HistoryStore {
    static let maxDays = 30

    /// All records, oldest first.
    static func load() -> [DayRecord] {
        AppGroup.defaults.codable([DayRecord].self, forKey: StoreKey.usageHistory) ?? []
    }

    /// Inserts or replaces the record for its day, keeping the newest
    /// `maxDays` records.
    static func record(_ record: DayRecord) {
        var records = load().filter { $0.dayKey != record.dayKey }
        records.append(record)
        records.sort { $0.dayKey < $1.dayKey }
        AppGroup.defaults.setCodable(Array(records.suffix(maxDays)), forKey: StoreKey.usageHistory)
    }

    /// The most recent `n` finished days, oldest first.
    static func lastDays(_ n: Int) -> [DayRecord] {
        Array(load().suffix(n))
    }
}
