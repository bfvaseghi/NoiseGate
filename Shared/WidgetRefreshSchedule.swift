import Foundation

/// Pure widget timing rules. Injected dates keep midnight, staleness, and DST
/// behavior deterministic in model tests.
enum WidgetRefreshSchedule {
    static func iOSNextRefresh(
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        let in15 = calendar.date(byAdding: .minute, value: 15, to: now)
            ?? now.addingTimeInterval(15 * 60)
        return min(in15, nextMidnight(after: now, calendar: calendar))
    }

    static func currentMacSnapshot(
        _ snapshot: UsageSnapshot,
        now: Date
    ) -> UsageSnapshot {
        var result = snapshot
        if result.monitoringIsActive,
           now.timeIntervalSince(result.updatedAt) > 45 {
            result.monitoringIsActive = false
        }
        return result
    }

    /// Widget reloads are a rationed system resource — asking for one every
    /// minute (or every few seconds, as a staleness deadline would) gets the
    /// widget throttled and therefore *staler* than a modest cadence. The Mac
    /// app reloads timelines itself whenever the numbers actually change, so
    /// this only has to be a safety net that lands on the midnight reset.
    static func macNextRefresh(
        snapshot: UsageSnapshot,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        let inFiveMinutes = calendar.date(byAdding: .minute, value: 5, to: now)
            ?? now.addingTimeInterval(300)
        return min(inFiveMinutes, nextMidnight(after: now, calendar: calendar))
    }

    /// Midnight is predictable. A future missed heartbeat is not: publishing
    /// a stale entry in advance can pause a healthy tracker until the next reload.
    static func midnightEntryDate(after now: Date, calendar: Calendar = .autoupdatingCurrent) -> Date {
        nextMidnight(after: now, calendar: calendar)
    }

    static func snapshotForDisplay(
        _ captured: UsageSnapshot,
        config: BudgetConfig,
        accuracy: WidgetAccuracy,
        now: Date
    ) -> UsageSnapshot {
        var result = captured
        if result.dayKey != DayKey.today(now) {
            result = UsageSnapshot(
                dayKey: DayKey.today(now),
                distractionBudgetMinutes: config.distractionBudget(on: now),
                messagesBudgetMinutes: config.messagesBudgetMinutes,
                distractionsConfigured: captured.distractionsConfigured,
                messagesConfigured: captured.messagesConfigured,
                isFloor: accuracy == .lowerBound,
                monitoringIsActive: accuracy == .lowerBound && captured.monitoringIsActive,
                updatedAt: captured.updatedAt
            )
        }
        result.isFloor = accuracy == .lowerBound
        return accuracy == .exact ? currentMacSnapshot(result, now: now) : result
    }

    /// Keep the outgoing day available to a scheduled midnight entry before
    /// either platform tracker has had a chance to file it into history.
    static func rolloverHistory(
        snapshot: UsageSnapshot,
        history: [DayRecord],
        accuracy: WidgetAccuracy
    ) -> [DayRecord] {
        guard snapshot.distractionsConfigured || snapshot.messagesConfigured else { return history }
        var record = DayRecord(snapshot: snapshot)
        record.isFloor = accuracy == .lowerBound
        return HistoryStore.canonicalized(history + [record])
    }

    private static func nextMidnight(
        after date: Date,
        calendar: Calendar
    ) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date)
            ?? date.addingTimeInterval(24 * 60 * 60)
        return calendar.startOfDay(for: tomorrow)
    }
}
