import Foundation

/// The widget-facing summary of today. Written by the iOS monitor extension
/// (threshold-based, so minutes are a floor) and by the macOS tracker (exact).
struct UsageSnapshot: Codable, Equatable {
    var dayKey: String = DayKey.today()
    var noiseMinutes: Int = 0
    var messagesMinutes: Int = 0
    var noiseBudgetMinutes: Int = 45
    var messagesBudgetMinutes: Int = 60
    /// True when minutes are threshold floors ("at least"), as on iOS.
    var isFloor: Bool = false
    var focusActive: Bool = false
    var updatedAt: Date = Date()

    var noiseFraction: Double {
        guard noiseBudgetMinutes > 0 else { return 0 }
        return min(1, Double(noiseMinutes) / Double(noiseBudgetMinutes))
    }

    var messagesFraction: Double {
        guard messagesBudgetMinutes > 0 else { return 0 }
        return min(1, Double(messagesMinutes) / Double(messagesBudgetMinutes))
    }

    /// Loads today's snapshot; a stale snapshot from a previous day is reset
    /// so the widget never shows yesterday's numbers.
    static func loadToday() -> UsageSnapshot {
        var snap = AppGroup.defaults.codable(UsageSnapshot.self, forKey: StoreKey.usageSnapshot)
            ?? UsageSnapshot()
        if snap.dayKey != DayKey.today() {
            let config = BudgetConfig.load()
            snap = UsageSnapshot(
                noiseBudgetMinutes: config.noiseBudgetMinutes,
                messagesBudgetMinutes: config.messagesBudgetMinutes,
                isFloor: snap.isFloor,
                focusActive: snap.focusActive
            )
        }
        return snap
    }

    func save() {
        AppGroup.defaults.setCodable(self, forKey: StoreKey.usageSnapshot)
    }
}
