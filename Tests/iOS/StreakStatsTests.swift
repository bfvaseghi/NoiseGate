import Foundation
import XCTest
@testable import NoiseGate

final class StreakStatsTests: XCTestCase {

    // MARK: - Helpers

    private func record(
        _ dayKey: String,
        distractionMinutes: Int,
        budget: Int = 45
    ) -> DayRecord {
        DayRecord(
            dayKey: dayKey,
            distractionMinutes: distractionMinutes,
            messagesMinutes: 0,
            distractionBudgetMinutes: budget,
            messagesBudgetMinutes: 60,
            isFloor: true
        )
    }

    private func snapshot(
        distractionMinutes: Int,
        budget: Int = 45,
        configured: Bool = true
    ) -> UsageSnapshot {
        UsageSnapshot(
            dayKey: "2026-08-24",
            distractionMinutes: distractionMinutes,
            distractionBudgetMinutes: budget,
            distractionsConfigured: configured,
            isFloor: true
        )
    }

    /// Seven finished days ending 2026-08-23, so 2026-08-24 is "today".
    private func week(_ minutes: [Int]) -> [DayRecord] {
        zip(17...23, minutes).map { day, value in
            record(String(format: "2026-08-%02d", day), distractionMinutes: value)
        }
    }

    // MARK: - Windowing

    func testTodayIsExcludedFromFinishedDayStatistics() {
        var records = week([10, 10, 10, 10, 10, 10, 10])
        // A record for today must not be counted as a finished day.
        records.append(record("2026-08-24", distractionMinutes: 300))

        let stats = StreakStats.distractions(
            records: records,
            snapshot: snapshot(distractionMinutes: 300),
            today: "2026-08-24"
        )

        XCTAssertEqual(stats.totalDays, 7)
        XCTAssertEqual(stats.averageMinutes, 10)
    }

    func testWindowKeepsOnlyTheMostRecentDays() {
        // Ten finished days; only the last seven should be averaged.
        let records = (14...23).map { day in
            record(
                String(format: "2026-08-%02d", day),
                distractionMinutes: day <= 16 ? 200 : 20
            )
        }

        let stats = StreakStats.distractions(
            records: records,
            snapshot: snapshot(distractionMinutes: 0),
            today: "2026-08-24"
        )

        XCTAssertEqual(stats.totalDays, 7)
        XCTAssertEqual(stats.averageMinutes, 20)
    }

    func testUnsortedRecordsAreOrderedBeforeAnalysis() {
        let stats = StreakStats.distractions(
            records: week([10, 10, 10, 10, 10, 10, 90]).shuffled(),
            snapshot: snapshot(distractionMinutes: 0),
            today: "2026-08-24"
        )

        // The newest day (08-23) reached budget, so the run must be zero
        // regardless of the order records arrived in.
        XCTAssertEqual(stats.underBudgetRun, 0)
        XCTAssertEqual(stats.underBudgetDays, 6)
    }

    // MARK: - Run length

    func testRunCountsConsecutiveUnderBudgetDaysFromMostRecent() {
        // 90 exceeds the 45 budget on 08-19; days after it are all under.
        let stats = StreakStats.distractions(
            records: week([10, 10, 90, 10, 10, 10, 10]),
            snapshot: snapshot(distractionMinutes: 0),
            today: "2026-08-24"
        )

        XCTAssertEqual(stats.underBudgetRun, 4)
        XCTAssertEqual(stats.underBudgetDays, 6)
    }

    func testReachingExactlyTheBudgetBreaksTheRun() {
        let stats = StreakStats.distractions(
            records: week([10, 10, 10, 10, 10, 10, 45]),
            snapshot: snapshot(distractionMinutes: 0),
            today: "2026-08-24"
        )

        XCTAssertEqual(stats.underBudgetRun, 0)
    }

    func testRunSpansBeyondTheAveragingWindow() {
        // Twelve consecutive under-budget finished days: the average window is
        // seven, but the run should report every one of them.
        let records = (12...23).map { day in
            record(String(format: "2026-08-%02d", day), distractionMinutes: 5)
        }

        let stats = StreakStats.distractions(
            records: records,
            snapshot: snapshot(distractionMinutes: 0),
            today: "2026-08-24"
        )

        XCTAssertEqual(stats.underBudgetRun, 12)
        XCTAssertEqual(stats.totalDays, 7)
    }

    // MARK: - Trend

    func testTrendIsNilWithoutEnoughPriorHistory() {
        let stats = StreakStats.distractions(
            records: week([10, 10, 10, 10, 10, 10, 10]),
            snapshot: snapshot(distractionMinutes: 0),
            today: "2026-08-24"
        )

        XCTAssertNil(stats.trendPercent)
    }

    func testTrendComparesRecentWindowAgainstPriorWindow() {
        // Prior seven days average 40; recent seven average 20 → −50%.
        var records = (10...16).map { day in
            record(String(format: "2026-08-%02d", day), distractionMinutes: 40)
        }
        records += (17...23).map { day in
            record(String(format: "2026-08-%02d", day), distractionMinutes: 20)
        }

        let stats = StreakStats.distractions(
            records: records,
            snapshot: snapshot(distractionMinutes: 0),
            today: "2026-08-24"
        )

        XCTAssertEqual(stats.priorAverageMinutes, 40)
        XCTAssertEqual(stats.averageMinutes, 20)
        XCTAssertEqual(stats.trendPercent, -50)
    }

    func testTrendIsNilWhenPriorWindowWasEmpty() {
        // Prior days exist but recorded nothing, so a percentage change
        // against zero would be meaningless rather than infinite.
        var records = (10...16).map { day in
            record(String(format: "2026-08-%02d", day), distractionMinutes: 0)
        }
        records += (17...23).map { day in
            record(String(format: "2026-08-%02d", day), distractionMinutes: 20)
        }

        let stats = StreakStats.distractions(
            records: records,
            snapshot: snapshot(distractionMinutes: 0),
            today: "2026-08-24"
        )

        XCTAssertNil(stats.trendPercent)
    }

    // MARK: - Empty and unconfigured states

    func testEmptyHistoryProducesZeroedSummary() {
        let stats = StreakStats.distractions(
            records: [],
            snapshot: snapshot(distractionMinutes: 0),
            today: "2026-08-24"
        )

        XCTAssertEqual(stats.totalDays, 0)
        XCTAssertEqual(stats.underBudgetDays, 0)
        XCTAssertEqual(stats.underBudgetRun, 0)
        XCTAssertEqual(stats.averageMinutes, 0)
        XCTAssertNil(stats.trendPercent)
    }

    func testTodayReachedBudgetRequiresAConfiguredLedger() {
        // Zero budget-vs-zero usage must not read as "reached" when the user
        // has not selected any apps yet.
        let unconfigured = StreakStats.distractions(
            records: [],
            snapshot: snapshot(distractionMinutes: 0, configured: false),
            today: "2026-08-24"
        )
        XCTAssertFalse(unconfigured.todayReachedBudget)

        let reached = StreakStats.distractions(
            records: [],
            snapshot: snapshot(distractionMinutes: 45, configured: true),
            today: "2026-08-24"
        )
        XCTAssertTrue(reached.todayReachedBudget)
    }

    func testPerDayBudgetChangesAreRespectedNotTodaysBudget() {
        // 30 minutes was over budget on a 20-minute day and under on a
        // 60-minute day; the stored per-day budget must decide.
        let records = [
            record("2026-08-22", distractionMinutes: 30, budget: 20),
            record("2026-08-23", distractionMinutes: 30, budget: 60)
        ]

        let stats = StreakStats.distractions(
            records: records,
            snapshot: snapshot(distractionMinutes: 0),
            today: "2026-08-24"
        )

        XCTAssertEqual(stats.underBudgetDays, 1)
        XCTAssertEqual(stats.underBudgetRun, 1)
    }
}
