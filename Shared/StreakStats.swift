import Foundation

/// Factual streak arithmetic over finished days plus today. Kept out of the
/// views so the day-boundary rules stay testable, and deliberately neutral:
/// these are counts, not congratulations.
enum StreakStats {
    struct Summary: Equatable {
        /// Consecutive most-recent finished days that stayed under budget.
        var underBudgetRun: Int = 0
        /// Finished days under budget within the window.
        var underBudgetDays: Int = 0
        /// Finished days counted in the window.
        var totalDays: Int = 0
        /// Mean minutes per finished day in the window.
        var averageMinutes: Int = 0
        /// Mean minutes of the finished days before the most recent 7, used
        /// only when there is enough history for the comparison to mean
        /// anything.
        var priorAverageMinutes: Int?
        /// True when today has already reached its budget.
        var todayReachedBudget: Bool = false

        /// Signed percentage change against the prior window, or nil when
        /// there is not enough history (or the prior window was empty).
        var trendPercent: Int? {
            guard let prior = priorAverageMinutes, prior > 0, totalDays >= 4 else { return nil }
            return Int(((Double(averageMinutes) - Double(prior)) / Double(prior) * 100).rounded())
        }
    }

    /// - Parameters:
    ///   - records: finished days, any order; today is excluded if present.
    ///   - snapshot: today's live snapshot, used only for `todayReachedBudget`.
    ///   - window: how many finished days to average over.
    static func distractions(
        records: [DayRecord],
        snapshot: UsageSnapshot,
        window: Int = 7,
        today: String = DayKey.today()
    ) -> Summary {
        let finished = records
            .filter { $0.dayKey != today }
            .sorted { $0.dayKey < $1.dayKey }

        var summary = Summary()
        summary.todayReachedBudget = snapshot.distractionsConfigured
            && snapshot.distractionMinutes >= snapshot.distractionBudgetMinutes

        let recent = Array(finished.suffix(window))
        summary.totalDays = recent.count
        summary.underBudgetDays = recent.filter { !$0.distractionReachedBudget }.count
        if !recent.isEmpty {
            summary.averageMinutes = recent.reduce(0) { $0 + $1.distractionMinutes } / recent.count
        }

        // Run length walks backwards from the most recent finished day.
        for record in finished.reversed() {
            if record.distractionReachedBudget { break }
            summary.underBudgetRun += 1
        }

        let prior = finished.dropLast(window).suffix(window)
        if prior.count >= 3 {
            summary.priorAverageMinutes = prior.reduce(0) { $0 + $1.distractionMinutes } / prior.count
        }
        return summary
    }
}
