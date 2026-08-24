import Foundation

/// User settings shared between the app, the monitor extension, and the widget.
/// NoiseGate only ever *observes* — there is no blocking anywhere in the app.
struct BudgetConfig: Codable, Equatable {
    /// Daily budget for the "noise" apps (the distracting ones), in minutes.
    var noiseBudgetMinutes: Int = 45
    /// Daily budget for Messages, in minutes. Tracked separately.
    var messagesBudgetMinutes: Int = 60
    /// Which budget milestones send a notification (subset of `nudgePercents`).
    var notifyAt: Set<Int> = [50, 80, 100]
    /// Whether the 150% / 200% past-budget notifications are sent.
    var overtimeNotifications: Bool = true
    /// macOS: show today's noise minutes next to the menu-bar icon.
    var showMinutesInMenuBar: Bool = false

    /// Percentages of a budget at which a nudge notification can be sent.
    static let nudgePercents: [Int] = [50, 80, 100]
    /// Percent steps used for threshold events, which also drive widget progress.
    static let progressPercents: [Int] = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
    /// Two check-ins past 100%, sent only while `overtimeNotifications` is on.
    static let overtimePercents: [Int] = [150, 200]

    init() {}

    /// Tolerant decoding: fields added in later versions fall back to their
    /// defaults instead of discarding the user's stored budgets.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        noiseBudgetMinutes = try c.decodeIfPresent(Int.self, forKey: .noiseBudgetMinutes) ?? 45
        messagesBudgetMinutes = try c.decodeIfPresent(Int.self, forKey: .messagesBudgetMinutes) ?? 60
        notifyAt = try c.decodeIfPresent(Set<Int>.self, forKey: .notifyAt) ?? [50, 80, 100]
        overtimeNotifications = try c.decodeIfPresent(Bool.self, forKey: .overtimeNotifications) ?? true
        showMinutesInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showMinutesInMenuBar) ?? false
    }

    /// Whether a given threshold percent should produce a notification.
    func notifies(atPercent percent: Int) -> Bool {
        percent > 100 ? overtimeNotifications : notifyAt.contains(percent)
    }

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
