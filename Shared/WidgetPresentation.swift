import Foundation

/// The two ledgers a widget can emphasize. This presentation layer is kept
/// free of WidgetKit so its privacy-sensitive copy and boundary states can be
/// covered by the app's model tests.
enum WidgetLedger: String, CaseIterable, Codable, Equatable {
    case distractions
    case messages

    var title: String {
        switch self {
        case .distractions: return "Distractions"
        case .messages: return "Messages"
        }
    }
}

enum WidgetUsageLevel: String, Equatable {
    case notConfigured
    case waitingForCheckpoint
    case clear
    case watch
    case high
    case reached
    case over
}

enum WidgetAccuracy: Equatable {
    /// Treat every value as a threshold-derived lower bound.
    case lowerBound
    /// Treat every value as exact tracker output.
    case exact
}

/// A truthful, platform-neutral rendering model for one ledger. iPhone values
/// remain lower bounds, while Mac values remain exact.
struct WidgetLedgerPresentation: Equatable {
    let ledger: WidgetLedger
    let minutes: Int
    let budgetMinutes: Int
    let isConfigured: Bool
    let isFloor: Bool
    let monitoringIsActive: Bool

    init(
        snapshot: UsageSnapshot,
        ledger: WidgetLedger,
        accuracy: WidgetAccuracy
    ) {
        self.ledger = ledger
        switch ledger {
        case .distractions:
            minutes = snapshot.distractionMinutes
            budgetMinutes = snapshot.distractionBudgetMinutes
            isConfigured = snapshot.distractionsConfigured
        case .messages:
            minutes = snapshot.messagesMinutes
            budgetMinutes = snapshot.messagesBudgetMinutes
            isConfigured = snapshot.messagesConfigured
        }
        switch accuracy {
        case .lowerBound: isFloor = true
        case .exact: isFloor = false
        }
        monitoringIsActive = snapshot.monitoringIsActive
    }

    var fraction: Double {
        guard isConfigured, budgetMinutes > 0 else { return 0 }
        return min(1, Double(minutes) / Double(budgetMinutes))
    }

    var progressPercent: Int {
        guard isConfigured, budgetMinutes > 0 else { return 0 }
        if isFloor {
            return (BudgetConfig.progressPercents + BudgetConfig.overtimePercents)
                .filter { percent in
                    let threshold = max(
                        1,
                        (Double(budgetMinutes) * Double(percent) / 100).rounded(.up)
                    )
                    return threshold <= Double(minutes)
                }
                .max() ?? 0
        }
        let rawPercent = (Double(minutes) * 100 / Double(budgetMinutes))
            .rounded(.down)
        return Int(min(100, max(0, rawPercent)))
    }

    var level: WidgetUsageLevel {
        guard isConfigured else { return .notConfigured }
        if isFloor && minutes == 0 { return .waitingForCheckpoint }
        if minutes > budgetMinutes { return .over }
        if minutes >= budgetMinutes { return .reached }
        if progressPercent >= 80 { return .high }
        if progressPercent >= 50 { return .watch }
        return .clear
    }

    var valueText: String {
        guard isConfigured else { return "—" }
        guard !isFloor || minutes > 0 else { return "—" }
        return "\(isFloor ? "≥" : "")\(minutes.asHoursMinutes)"
    }

    var valueAndBudgetText: String {
        switch level {
        case .notConfigured:
            return "Not set"
        case .waitingForCheckpoint:
            return "No checkpoint yet"
        default:
            return "\(valueText) / \(budgetMinutes.asHoursMinutes)"
        }
    }

    /// Hours-only reading for the Lock Screen circle, where "≥1h 05m" does
    /// not fit at a legible size. Dropping the minutes keeps a floor true,
    /// so only floors are shortened; an exact value is never rounded down.
    var compactValueText: String {
        guard isConfigured, isFloor, minutes >= 60 else { return valueText }
        return "≥\(minutes / 60)h"
    }

    /// The small family's status line: the facts of `signalText` in the
    /// width of a 126 pt canvas at 12 pt, with the budget named because the
    /// small ring has no room for it.
    var compactSignalText: String {
        guard isConfigured else { return "Choose apps" }
        guard monitoringIsActive else { return "Tracking paused" }
        switch level {
        case .notConfigured:
            return "Choose apps"
        case .waitingForCheckpoint:
            return "No checkpoint yet"
        case .clear, .watch, .high:
            return "\(isFloor ? "≥" : "")\(progressPercent)% of \(budgetMinutes.asHoursMinutes)"
        case .reached:
            return isFloor ? "Budget crossed" : "Budget reached"
        case .over:
            return "\(isFloor ? "≥" : "")\((minutes - budgetMinutes).asHoursMinutes) over"
        }
    }

    /// The most characters the inline Lock Screen line carries. Beside its
    /// glyph the line is about 234 pt wide on an iPhone 15/16 Pro, which the
    /// system's inline face fills at roughly 25 characters; the system cuts
    /// anything longer mid-word with an ellipsis, so a longer reading drops
    /// its budget, then its value, and is never truncated.
    static let inlineCharacterBudget = 24

    /// The inline Lock Screen line: ledger, state and value.
    var inlineText: String {
        let name = ledger.title
        let budget = budgetMinutes.asHoursMinutes
        let candidates: [String]
        switch level {
        case .notConfigured:
            return "\(name) not set"
        case .waitingForCheckpoint:
            // The app's dash for "nothing measured yet" and the budget it is
            // measured against; "no checkpoint" beside the ledger name runs
            // past the line.
            return "\(name) \(valueText) / \(budget)"
        default:
            candidates = monitoringIsActive
                ? ["\(name) \(valueText) / \(budget)", "\(name) \(valueText)"]
                : ["\(name) paused \(valueText)", "\(name) paused"]
        }
        return candidates.first { $0.count <= Self.inlineCharacterBudget }
            ?? candidates[candidates.count - 1]
    }

    /// A full sentence for Siri and Shortcuts. It reads `isFloor` from the
    /// same place the widget does, so a spoken answer can never claim more
    /// precision than the screen shows.
    var spokenSummary: String {
        let name = ledger == .distractions ? "Distractions" : "Messages"
        switch level {
        case .notConfigured:
            return ledger == .distractions
                ? "No distracting apps are selected yet."
                : "No messaging apps are selected yet."
        case .waitingForCheckpoint:
            return "No \(name.lowercased()) checkpoint has been crossed today."
        default:
            let amount = isFloor
                ? "at least \(minutes.asHoursMinutes)"
                : minutes.asHoursMinutes
            let verdict = minutes >= budgetMinutes
                ? " That is past today's \(budgetMinutes.asHoursMinutes) budget."
                : ""
            return "\(name): \(amount) today, against a "
                + "\(budgetMinutes.asHoursMinutes) budget.\(verdict)"
        }
    }

    var signalText: String {
        switch level {
        case .notConfigured:
            return ledger == .distractions
                ? "Choose distracting apps" : "Choose messaging apps"
        case .waitingForCheckpoint:
            return "No checkpoint yet"
        case .clear, .watch, .high:
            return "\(isFloor ? "At least " : "")\(progressPercent)% of budget"
        case .reached:
            return isFloor ? "Budget crossed" : "Budget reached"
        case .over:
            return isFloor
                ? "At least \((minutes - budgetMinutes).asHoursMinutes) over budget"
                : "\((minutes - budgetMinutes).asHoursMinutes) over budget"
        }
    }

    var accessibilityValue: String {
        switch level {
        case .notConfigured:
            return "Not configured"
        case .waitingForCheckpoint:
            return "No checkpoint reached yet"
        default:
            let qualifier = isFloor ? "At least " : ""
            let state: String
            switch level {
            case .reached: state = ", budget crossed"
            case .over: state = ", over budget"
            default: state = ""
            }
            return "\(qualifier)\(minutes) minutes of a \(budgetMinutes) minute budget\(state)"
        }
    }
}

enum WidgetWeekStatus: String, Equatable {
    case noRecord
    case noCheckpoint
    case zero
    case checkpoint
    case reached
}

struct WidgetWeekDay: Equatable, Identifiable {
    let dayKey: String
    let date: Date
    let minutes: Int
    let budgetMinutes: Int
    let isFloor: Bool
    let isToday: Bool
    let hasRecord: Bool

    var id: String { dayKey }

    var fraction: Double {
        guard hasRecord, budgetMinutes > 0 else { return 0 }
        return min(1, Double(minutes) / Double(budgetMinutes))
    }

    var status: WidgetWeekStatus {
        guard hasRecord else { return .noRecord }
        if minutes >= budgetMinutes { return .reached }
        if minutes > 0 { return .checkpoint }
        return isFloor ? .noCheckpoint : .zero
    }
}

/// Seven calendar days ending today. Missing or zero-valued iPhone records are
/// never described as "under budget" because the widget sees checkpoints, not
/// exact Screen Time.
struct WidgetWeekSummary: Equatable {
    let ledger: WidgetLedger
    let days: [WidgetWeekDay]

    init(
        snapshot: UsageSnapshot,
        history: [DayRecord],
        ledger: WidgetLedger,
        accuracy: WidgetAccuracy,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.ledger = ledger
        var byDay = Dictionary(
            uniqueKeysWithValues: HistoryStore.canonicalized(history).map {
                ($0.dayKey, $0)
            }
        )
        let todayKey = widgetDayKey(for: now, calendar: calendar)
        byDay.removeValue(forKey: todayKey)
        if snapshot.dayKey == todayKey {
            let configured = ledger == .distractions
                ? snapshot.distractionsConfigured : snapshot.messagesConfigured
            if configured {
                byDay[todayKey] = DayRecord(snapshot: snapshot)
            } else {
                byDay.removeValue(forKey: todayKey)
            }
        }

        days = (-6...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: now) else {
                return nil
            }
            let key = widgetDayKey(for: date, calendar: calendar)
            let record = byDay[key]
            let minutes: Int
            let budget: Int
            switch ledger {
            case .distractions:
                minutes = record?.distractionMinutes ?? 0
                budget = record?.distractionBudgetMinutes
                    ?? snapshot.distractionBudgetMinutes
            case .messages:
                minutes = record?.messagesMinutes ?? 0
                budget = record?.messagesBudgetMinutes
                    ?? snapshot.messagesBudgetMinutes
            }
            return WidgetWeekDay(
                dayKey: key,
                date: date,
                minutes: minutes,
                budgetMinutes: budget,
                isFloor: accuracy == .lowerBound,
                isToday: key == todayKey,
                hasRecord: record != nil
            )
        }
    }

    var reachedDayCount: Int {
        days.filter { $0.status == .reached }.count
    }

    var checkpointDayCount: Int {
        days.filter { $0.status == .checkpoint }.count
    }

    /// "Confirmed crossing" is lower-bound language: on iPhone a day only
    /// counts once a threshold actually fired. Mac values are exact, so there
    /// it states plainly how many days reached the budget.
    var summaryText: String {
        let isFloor = days.first?.isFloor ?? true
        if isFloor {
            switch reachedDayCount {
            case 0: return "No confirmed crossings"
            case 1: return "1 confirmed crossing"
            default: return "\(reachedDayCount) confirmed crossings"
            }
        }
        switch reachedDayCount {
        case 0: return "Budget not reached"
        case 1: return "Budget reached on 1 day"
        default: return "Budget reached on \(reachedDayCount) days"
        }
    }
}

/// The medium and large families' streak line: finished calendar days,
/// counted back from yesterday until a day is missing or reached its own
/// stored budget. A missing day ends the count instead of being bridged —
/// a day the monitor never filed is not a day without a crossing — which is
/// why this does not reuse `StreakStats`, whose run walks records.
struct WidgetStreakLine: Equatable {
    let text: String?

    init(
        snapshot: UsageSnapshot,
        history: [DayRecord],
        ledger: WidgetLedger,
        accuracy: WidgetAccuracy,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) {
        let configured: Bool
        let todayReached: Bool
        switch ledger {
        case .distractions:
            configured = snapshot.distractionsConfigured
            todayReached = snapshot.distractionMinutes >= snapshot.distractionBudgetMinutes
        case .messages:
            configured = snapshot.messagesConfigured
            todayReached = snapshot.messagesMinutes >= snapshot.messagesBudgetMinutes
        }
        guard configured else {
            text = nil
            return
        }
        if snapshot.dayKey == widgetDayKey(for: now, calendar: calendar), todayReached {
            text = "Resets at midnight"
            return
        }

        let byDay = Dictionary(
            uniqueKeysWithValues: HistoryStore.canonicalized(history).map {
                ($0.dayKey, $0)
            }
        )
        var run = 0
        var stoppedAtReachedDay = false
        for offset in 1...HistoryStore.maxDays {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now),
                  let record = byDay[widgetDayKey(for: date, calendar: calendar)] else {
                break
            }
            let reached = ledger == .distractions
                ? record.distractionReachedBudget : record.messagesReachedBudget
            if reached {
                stoppedAtReachedDay = true
                break
            }
            run += 1
        }

        let isFloor = accuracy == .lowerBound
        switch run {
        case 0:
            guard stoppedAtReachedDay else {
                text = nil
                return
            }
            text = isFloor ? "Crossed yesterday" : "Budget reached yesterday"
        case 1:
            text = isFloor ? "1 day without a crossing" : "1 day under budget"
        default:
            text = isFloor ? "\(run) days without a crossing" : "\(run) days under budget"
        }
    }
}

/// The "when" beside the number. On iPhone it is the snapshot's own write
/// time — a stamp at the eyebrow's trailing edge rather than "Checkpoint",
/// because a budget or selection save bumps `updatedAt` too — shown only
/// while the snapshot is today's and holds a checkpoint. On the Mac the
/// tracker heartbeats every 30 s, so a write time says nothing; a sentence
/// says whether the tracker is live and, when it is not, when it last was.
enum WidgetClockLine {
    /// The shortened local time of the last write, or nil when no time may
    /// be shown for this platform and state.
    static func time(
        snapshot: UsageSnapshot,
        ledger: WidgetLedger,
        accuracy: WidgetAccuracy,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> String? {
        let today = widgetDayKey(for: now, calendar: calendar)
        let writtenToday = widgetDayKey(for: snapshot.updatedAt, calendar: calendar) == today
        switch accuracy {
        case .lowerBound:
            let level = WidgetLedgerPresentation(
                snapshot: snapshot,
                ledger: ledger,
                accuracy: accuracy
            ).level
            guard snapshot.dayKey == today,
                  writtenToday,
                  level != .notConfigured,
                  level != .waitingForCheckpoint else { return nil }
            return formatted(snapshot.updatedAt)
        case .exact:
            guard !snapshot.monitoringIsActive, writtenToday else { return nil }
            return formatted(snapshot.updatedAt)
        }
    }

    /// The stamp at the trailing edge of the medium's eyebrow row: the write
    /// time alone, iPhone only. A bare time in that corner is the Lock
    /// Screen's own "as of" idiom; the Mac says live or paused in words.
    static func stamp(
        snapshot: UsageSnapshot,
        ledger: WidgetLedger,
        accuracy: WidgetAccuracy,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> String? {
        guard accuracy == .lowerBound else { return nil }
        return time(
            snapshot: snapshot,
            ledger: ledger,
            accuracy: accuracy,
            now: now,
            calendar: calendar
        )
    }

    /// The running-text line for the medium column, Mac only: whether the
    /// tracker is live and, when it is not, when it last was.
    static func text(
        snapshot: UsageSnapshot,
        ledger: WidgetLedger,
        accuracy: WidgetAccuracy,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> String? {
        switch accuracy {
        case .lowerBound:
            return nil
        case .exact:
            guard !snapshot.monitoringIsActive else { return "Tracking on this Mac" }
            let time = time(
                snapshot: snapshot,
                ledger: ledger,
                accuracy: accuracy,
                now: now,
                calendar: calendar
            )
            return time.map { "Paused on this Mac · \($0)" } ?? "Paused on this Mac"
        }
    }

    /// The small-caps line at the top right of the large family.
    static func masthead(
        snapshot: UsageSnapshot,
        ledger: WidgetLedger,
        accuracy: WidgetAccuracy,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> String? {
        let time = time(
            snapshot: snapshot,
            ledger: ledger,
            accuracy: accuracy,
            now: now,
            calendar: calendar
        )
        switch accuracy {
        case .lowerBound:
            return time.map { "UPDATED \($0)" }
        case .exact:
            guard !snapshot.monitoringIsActive else { return "THIS MAC · LIVE" }
            return time.map { "THIS MAC · PAUSED \($0)" } ?? "THIS MAC · PAUSED"
        }
    }

    private static func formatted(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

/// `DayKey.today` for an injected calendar, so the week, streak and clock
/// stay deterministic in tests and previews.
private func widgetDayKey(for date: Date, calendar: Calendar) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    guard let year = parts.year, let month = parts.month, let day = parts.day else {
        return "1970-01-01"
    }
    return String(format: "%04d-%02d-%02d", year, month, day)
}
