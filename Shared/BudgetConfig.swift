import Foundation

/// User settings shared between the app, the monitor extension, and the widget.
struct BudgetConfig: Codable, Equatable {
    /// Daily budget for the "noise" apps (social media etc.), in minutes.
    var noiseBudgetMinutes: Int = 45
    /// Daily budget for messaging, in minutes. Tracked separately, never blocked.
    var messagesBudgetMinutes: Int = 60
    /// When the noise budget hits 100%, block the noise apps for the rest of the day.
    var blockNoiseAtBudget: Bool = true
    /// Scheduled quiet hours during which noise apps are always blocked.
    var quietHoursEnabled: Bool = false
    /// Minutes from midnight, local time (default 22:00 → 07:00).
    var quietStartMinutes: Int = 22 * 60
    var quietEndMinutes: Int = 7 * 60

    /// Percentages of a budget at which a nudge notification is sent.
    static let nudgePercents: [Int] = [50, 80, 100]
    /// Percent steps used for threshold events, which also drive widget progress.
    static let progressPercents: [Int] = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]

    static func load() -> BudgetConfig {
        AppGroup.defaults.codable(BudgetConfig.self, forKey: StoreKey.budgetConfig) ?? BudgetConfig()
    }

    func save() {
        AppGroup.defaults.setCodable(self, forKey: StoreKey.budgetConfig)
    }
}

extension Int {
    /// "1h 05m" style formatting for a value in minutes.
    var asHoursMinutes: String {
        let h = self / 60, m = self % 60
        if h == 0 { return "\(m)m" }
        return String(format: "%dh %02dm", h, m)
    }
}
