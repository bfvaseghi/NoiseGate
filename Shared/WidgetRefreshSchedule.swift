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

    /// When the tracker should be considered to have stopped heartbeating.
    /// Rendered as a second timeline entry rather than a reload request, so
    /// the paused state appears on time without spending refresh budget.
    static func macStaleEntryDate(
        snapshot: UsageSnapshot,
        now: Date
    ) -> Date? {
        guard snapshot.monitoringIsActive else { return nil }
        let deadline = snapshot.updatedAt.addingTimeInterval(46)
        return deadline > now ? deadline : nil
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
