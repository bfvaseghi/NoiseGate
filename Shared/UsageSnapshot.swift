import Foundation

/// The widget-facing summary of today. Written by the iOS monitor extension
/// (threshold-based, so minutes are a floor) and by the macOS tracker (exact).
struct UsageSnapshot: Codable, Equatable {
    var dayKey: String = DayKey.today()
    var distractionMinutes: Int = 0
    var messagesMinutes: Int = 0
    var distractionBudgetMinutes: Int = 45
    var messagesBudgetMinutes: Int = 60
    /// Whether each ledger currently has at least one effective selection.
    var distractionsConfigured: Bool = false
    var messagesConfigured: Bool = false
    /// True when minutes are threshold floors ("at least"), as on iOS.
    var isFloor: Bool = false
    /// Whether the platform tracker successfully started for the current rules.
    var monitoringIsActive: Bool = false
    var updatedAt: Date = Date()

    init(
        dayKey: String = DayKey.today(),
        distractionMinutes: Int = 0,
        messagesMinutes: Int = 0,
        distractionBudgetMinutes: Int = 45,
        messagesBudgetMinutes: Int = 60,
        distractionsConfigured: Bool = false,
        messagesConfigured: Bool = false,
        isFloor: Bool = false,
        monitoringIsActive: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.dayKey = dayKey
        self.distractionMinutes = max(0, distractionMinutes)
        self.messagesMinutes = max(0, messagesMinutes)
        self.distractionBudgetMinutes = max(1, distractionBudgetMinutes)
        self.messagesBudgetMinutes = max(1, messagesBudgetMinutes)
        self.distractionsConfigured = distractionsConfigured
        self.messagesConfigured = messagesConfigured
        self.isFloor = isFloor
        self.monitoringIsActive = monitoringIsActive
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case dayKey
        case distractionMinutes
        case noiseMinutes // v1 migration
        case messagesMinutes
        case distractionBudgetMinutes
        case noiseBudgetMinutes // v1 migration
        case messagesBudgetMinutes
        case distractionsConfigured
        case messagesConfigured
        case isFloor
        case monitoringIsActive
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            dayKey: try c.decodeIfPresent(String.self, forKey: .dayKey) ?? DayKey.today(),
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
            distractionsConfigured: try c.decodeIfPresent(
                Bool.self,
                forKey: .distractionsConfigured
            ) ?? false,
            messagesConfigured: try c.decodeIfPresent(
                Bool.self,
                forKey: .messagesConfigured
            ) ?? false,
            isFloor: try c.decodeIfPresent(Bool.self, forKey: .isFloor) ?? false,
            monitoringIsActive: try c.decodeIfPresent(
                Bool.self,
                forKey: .monitoringIsActive
            ) ?? false,
            updatedAt: try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dayKey, forKey: .dayKey)
        try c.encode(distractionMinutes, forKey: .distractionMinutes)
        try c.encode(messagesMinutes, forKey: .messagesMinutes)
        try c.encode(distractionBudgetMinutes, forKey: .distractionBudgetMinutes)
        try c.encode(messagesBudgetMinutes, forKey: .messagesBudgetMinutes)
        try c.encode(distractionsConfigured, forKey: .distractionsConfigured)
        try c.encode(messagesConfigured, forKey: .messagesConfigured)
        try c.encode(isFloor, forKey: .isFloor)
        try c.encode(monitoringIsActive, forKey: .monitoringIsActive)
        try c.encode(updatedAt, forKey: .updatedAt)
    }

    var distractionFraction: Double {
        guard distractionsConfigured, distractionBudgetMinutes > 0 else { return 0 }
        return min(1, Double(distractionMinutes) / Double(distractionBudgetMinutes))
    }

    var messagesFraction: Double {
        guard messagesConfigured, messagesBudgetMinutes > 0 else { return 0 }
        return min(1, Double(messagesMinutes) / Double(messagesBudgetMinutes))
    }

    /// Loads today's snapshot; a stale snapshot from a previous day is reset
    /// so the widget never shows yesterday's numbers.
    static func loadToday() -> UsageSnapshot {
        var snap = SharedStore.shared.load(UsageSnapshot.self, forKey: StoreKey.usageSnapshot)
            ?? UsageSnapshot()
        if snap.dayKey != DayKey.today() {
            let config = BudgetConfig.load()
            snap = UsageSnapshot(
                distractionBudgetMinutes: config.distractionBudget(on: .now),
                messagesBudgetMinutes: config.messagesBudgetMinutes,
                distractionsConfigured: snap.distractionsConfigured,
                messagesConfigured: snap.messagesConfigured,
                isFloor: snap.isFloor,
                monitoringIsActive: snap.monitoringIsActive,
                updatedAt: snap.updatedAt
            )
        }
        return snap
    }

    func save() {
        SharedStore.shared.save(self, forKey: StoreKey.usageSnapshot)
    }
}
