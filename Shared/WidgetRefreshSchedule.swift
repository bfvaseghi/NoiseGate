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

    static func macNextRefresh(
        snapshot: UsageSnapshot,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        let refresh: Date
        if snapshot.monitoringIsActive {
            let oneMinute = calendar.date(byAdding: .minute, value: 1, to: now)
                ?? now.addingTimeInterval(60)
            let staleDeadline = snapshot.updatedAt.addingTimeInterval(46)
            refresh = max(now.addingTimeInterval(1), min(oneMinute, staleDeadline))
        } else {
            refresh = calendar.date(byAdding: .minute, value: 5, to: now)
                ?? now.addingTimeInterval(300)
        }
        return min(refresh, nextMidnight(after: now, calendar: calendar))
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
