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
        let todayKey = Self.dayKey(for: now, calendar: calendar)
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
            let key = Self.dayKey(for: date, calendar: calendar)
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

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            return "1970-01-01"
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
