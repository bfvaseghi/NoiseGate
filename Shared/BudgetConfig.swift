import Foundation

/// User settings shared between the app, the monitor extension, and the widget.
/// NoiseGate only ever *observes* — there is no blocking anywhere in the app.
struct BudgetConfig: Codable, Equatable {
    /// Daily budget for explicitly selected distracting apps, in minutes.
    var distractionBudgetMinutes: Int = 45
    /// Daily budget for Messages, in minutes. Tracked separately.
    var messagesBudgetMinutes: Int = 60
    /// Whether Saturday and Sunday carry their own Distractions target. One
    /// daily number cannot serve both a working Tuesday and a free Saturday.
    var weekendBudgetsEnabled: Bool = false
    /// Distractions budget applied on weekend days when the above is on.
    /// Messages deliberately keeps a single number: replying to people does
    /// not have the same weekday/weekend asymmetry that scrolling does.
    var weekendDistractionBudgetMinutes: Int = 75
    /// Master notification switch. Threshold tracking and widgets still work off.
    var notificationsEnabled: Bool = true
    /// Which budget milestones send a notification (subset of `nudgePercents`).
    var notifyAt: Set<Int> = [50, 80, 100]
    /// Whether the 150% / 200% past-budget notifications are sent.
    var overtimeNotifications: Bool = true
    /// macOS: show today's distraction minutes next to the menu-bar icon.
    var showMinutesInMenuBar: Bool = false

    /// Percentages of a budget at which a nudge notification can be sent.
    static let nudgePercents: [Int] = [50, 80, 100]
    /// Percent steps used for threshold events, which also drive widget progress.
    static let progressPercents: [Int] = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
    /// Two check-ins past 100%, sent only while `overtimeNotifications` is on.
    static let overtimePercents: [Int] = [150, 200]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case distractionBudgetMinutes
        case noiseBudgetMinutes // v1 migration
        case messagesBudgetMinutes
        case weekendBudgetsEnabled
        case weekendDistractionBudgetMinutes
        case notificationsEnabled
        case notifyAt
        case overtimeNotifications
        case showMinutesInMenuBar
    }

    /// Tolerant decoding: fields added in later versions fall back to their
    /// defaults instead of discarding the user's stored budgets.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        distractionBudgetMinutes = try c.decodeIfPresent(
            Int.self,
            forKey: .distractionBudgetMinutes
        ) ?? c.decodeIfPresent(Int.self, forKey: .noiseBudgetMinutes) ?? 45
        messagesBudgetMinutes = try c.decodeIfPresent(Int.self, forKey: .messagesBudgetMinutes) ?? 60
        weekendBudgetsEnabled = try c.decodeIfPresent(
            Bool.self,
            forKey: .weekendBudgetsEnabled
        ) ?? false
        weekendDistractionBudgetMinutes = try c.decodeIfPresent(
            Int.self,
            forKey: .weekendDistractionBudgetMinutes
        ) ?? 75
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        notifyAt = try c.decodeIfPresent(Set<Int>.self, forKey: .notifyAt) ?? [50, 80, 100]
        overtimeNotifications = try c.decodeIfPresent(Bool.self, forKey: .overtimeNotifications) ?? true
        showMinutesInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showMinutesInMenuBar) ?? false
        normalize()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(distractionBudgetMinutes, forKey: .distractionBudgetMinutes)
        try c.encode(messagesBudgetMinutes, forKey: .messagesBudgetMinutes)
        try c.encode(weekendBudgetsEnabled, forKey: .weekendBudgetsEnabled)
        try c.encode(
            weekendDistractionBudgetMinutes,
            forKey: .weekendDistractionBudgetMinutes
        )
        try c.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try c.encode(notifyAt, forKey: .notifyAt)
        try c.encode(overtimeNotifications, forKey: .overtimeNotifications)
        try c.encode(showMinutesInMenuBar, forKey: .showMinutesInMenuBar)
    }

    /// The Distractions budget that applies on a given day. `isDateInWeekend`
    /// follows the user's own calendar rather than hardcoding Saturday and
    /// Sunday, so this stays correct outside a Mon-Fri working week.
    func distractionBudget(on date: Date, calendar: Calendar = .current) -> Int {
        guard weekendBudgetsEnabled, calendar.isDateInWeekend(date) else {
            return distractionBudgetMinutes
        }
        return weekendDistractionBudgetMinutes
    }

    /// The budget a ledger is judged against on a given day. `kind` matches
    /// the threshold-event vocabulary so callers can pass an event's kind
    /// straight through.
    func budget(kind: String, on date: Date, calendar: Calendar = .current) -> Int {
        kind == "msg"
            ? messagesBudgetMinutes
            : distractionBudget(on: date, calendar: calendar)
    }

    /// Whether a given threshold percent should produce a notification.
    func notifies(atPercent percent: Int) -> Bool {
        notificationsEnabled
            && (percent > 100 ? overtimeNotifications : notifyAt.contains(percent))
    }

    static func load() -> BudgetConfig {
        var value = SharedStore.shared.load(BudgetConfig.self, forKey: StoreKey.budgetConfig)
            ?? BudgetConfig()
        let original = value
        value.normalize()
        if value != original { value.save() }
        return value
    }

    func save() {
        var value = self
        value.normalize()
        SharedStore.shared.save(value, forKey: StoreKey.budgetConfig)
    }

    mutating func normalize() {
        distractionBudgetMinutes = min(480, max(5, distractionBudgetMinutes))
        messagesBudgetMinutes = min(480, max(5, messagesBudgetMinutes))
        weekendDistractionBudgetMinutes = min(480, max(5, weekendDistractionBudgetMinutes))
        notifyAt.formIntersection(Set(Self.nudgePercents))
    }
}

extension Int {
    /// "1h 05m" style formatting for a value in minutes.
    var asHoursMinutes: String {
        let value = Swift.max(0, self)
        let h = value / 60, m = value % 60
        if h == 0 { return "\(m)m" }
        return String(format: "%dh %02dm", h, m)
    }
}
