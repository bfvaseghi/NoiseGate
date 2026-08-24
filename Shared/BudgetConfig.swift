import Foundation

/// User settings shared between the app, the monitor extension, and the widget.
/// NoiseGate only ever *observes* — there is no blocking anywhere in the app.
struct BudgetConfig: Codable, Equatable {
    /// Daily budget for the "noise" apps (the distracting ones), in minutes.
    var noiseBudgetMinutes: Int = 45
    /// Daily budget for Messages, in minutes. Tracked separately.
    var messagesBudgetMinutes: Int = 60

    /// Percentages of a budget at which a nudge notification is sent.
    static let nudgePercents: [Int] = [50, 80, 100]
    /// Percent steps used for threshold events, which also drive widget progress.
    static let progressPercents: [Int] = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
    /// Two gentle check-ins past 100%, in case the day got away from you.
    static let overtimePercents: [Int] = [150, 200]

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
