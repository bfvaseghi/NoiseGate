import Foundation

/// One finished day of usage. On iOS the minutes are threshold floors
/// (`isFloor == true`); on macOS they are exact tracker totals. Records are
/// per-device — iPhone/iPad and Mac each keep their own app-group store.
struct DayRecord: Codable, Equatable, Identifiable {
    let dayKey: String
    var distractionMinutes: Int
    var messagesMinutes: Int
    var distractionBudgetMinutes: Int
    var messagesBudgetMinutes: Int
    var isFloor: Bool

    init(
        dayKey: String,
        distractionMinutes: Int,
        messagesMinutes: Int,
        distractionBudgetMinutes: Int,
        messagesBudgetMinutes: Int,
        isFloor: Bool
    ) {
        self.dayKey = dayKey
        self.distractionMinutes = max(0, distractionMinutes)
        self.messagesMinutes = max(0, messagesMinutes)
        self.distractionBudgetMinutes = max(1, distractionBudgetMinutes)
        self.messagesBudgetMinutes = max(1, messagesBudgetMinutes)
        self.isFloor = isFloor
    }

    init(snapshot: UsageSnapshot) {
        self.init(
            dayKey: snapshot.dayKey,
            distractionMinutes: snapshot.distractionMinutes,
            messagesMinutes: snapshot.messagesMinutes,
            distractionBudgetMinutes: snapshot.distractionBudgetMinutes,
            messagesBudgetMinutes: snapshot.messagesBudgetMinutes,
            isFloor: snapshot.isFloor
        )
    }

    private enum CodingKeys: String, CodingKey {
        case dayKey
        case distractionMinutes
        case noiseMinutes
        case messagesMinutes
        case distractionBudgetMinutes
        case noiseBudgetMinutes
        case messagesBudgetMinutes
        case isFloor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            dayKey: try c.decode(String.self, forKey: .dayKey),
            distractionMinutes: try c.decodeIfPresent(
                Int.self,
                forKey: .distractionMinutes
            ) ?? c.decodeIfPresent(Int.self, forKey: .noiseMinutes) ?? 0,
            messagesMinutes: try c.decodeIfPresent(Int.self, forKey: .messagesMinutes) ?? 0,
            distractionBudgetMinutes: try c.decodeIfPresent(
                Int.self,
                forKey: .distractionBudgetMinutes
            ) ?? c.decodeIfPresent(Int.self, forKey: .noiseBudgetMinutes) ?? 45,
            messagesBudgetMinutes: try c.decodeIfPresent(
                Int.self,
                forKey: .messagesBudgetMinutes
            ) ?? 60,
            isFloor: try c.decodeIfPresent(Bool.self, forKey: .isFloor) ?? false
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dayKey, forKey: .dayKey)
        try c.encode(distractionMinutes, forKey: .distractionMinutes)
        try c.encode(messagesMinutes, forKey: .messagesMinutes)
        try c.encode(distractionBudgetMinutes, forKey: .distractionBudgetMinutes)
        try c.encode(messagesBudgetMinutes, forKey: .messagesBudgetMinutes)
        try c.encode(isFloor, forKey: .isFloor)
    }

    var id: String { dayKey }
    var date: Date { DayKey.date(from: dayKey) ?? .distantPast }
    var distractionReachedBudget: Bool {
        distractionBudgetMinutes > 0 && distractionMinutes >= distractionBudgetMinutes
    }
    var messagesReachedBudget: Bool {
        messagesBudgetMinutes > 0 && messagesMinutes >= messagesBudgetMinutes
    }
}

/// Rolling per-day history, written at the daily rollover (iOS monitor
/// extension / macOS tracker) and read by the stats card and Mac chart.
enum HistoryStore {
    static let maxDays = 30

    /// Files a stale widget snapshot before another process replaces it with
    /// today's values. Calling this more than once is safe because `record`
    /// replaces the existing record for the same day.
    static func recordFinishedSnapshot(
        _ snapshot: UsageSnapshot,
        today: String = DayKey.today()
    ) {
        guard snapshot.dayKey != today else { return }
        record(DayRecord(snapshot: snapshot))
    }

    /// All records, oldest first.
    static func load() -> [DayRecord] {
        canonicalized(
            SharedStore.shared.load(
                [DayRecord].self,
                forKey: StoreKey.usageHistory
            ) ?? []
        )
    }

    /// Repairs malformed legacy history in memory. The newest duplicate wins,
    /// invalid day keys disappear, and callers always receive chronological
    /// records. This prevents a duplicate key from crashing a report view.
    static func canonicalized(_ records: [DayRecord]) -> [DayRecord] {
        var byDay: [String: DayRecord] = [:]
        for record in records where DayKey.date(from: record.dayKey) != nil {
            byDay[record.dayKey] = record
        }
        return byDay.values.sorted { $0.dayKey < $1.dayKey }
    }

    /// Inserts or replaces the record for its day, keeping the newest
    /// `maxDays` records.
    static func record(_ record: DayRecord) {
        guard DayKey.date(from: record.dayKey) != nil else { return }
        _ = SharedStore.shared.update(
            [DayRecord].self,
            forKey: StoreKey.usageHistory,
            default: []
        ) { records in
            records.append(record)
            records = Array(canonicalized(records).suffix(maxDays))
        }
    }

    /// The most recent `n` finished days, oldest first.
    static func lastDays(_ n: Int) -> [DayRecord] {
        Array(load().suffix(n))
    }
}
