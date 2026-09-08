import Foundation
import XCTest
@testable import NoiseGate

final class SignalRegressionTests: XCTestCase {
    func testDayKeysRejectNormalizedAndNonCanonicalDates() throws {
        for invalid in ["2026-02-31", "2026-02-29", "2026-13-01", "2026-00-01",
                        "2026-9-08", "2026-09-8", "0000-01-01", "2026-09-08 "] {
            XCTAssertNil(DayKey.date(from: invalid), invalid)
        }
        let leapDay = try XCTUnwrap(DayKey.date(from: "2024-02-29"))
        XCTAssertEqual(DayKey.today(leapDay), "2024-02-29")
    }

    func testIOSExportForcesMinimumsForLegacyRecords() {
        let record = DayRecord(dayKey: "2026-09-07", distractionMinutes: 32,
                               messagesMinutes: 6, distractionBudgetMinutes: 45,
                               messagesBudgetMinutes: 60, isFloor: false)
        let csv = HistoryExport.csv([record], forceLowerBound: true)
        XCTAssertTrue(csv.contains("2026-09-07,32,45,6,60,at_least"))
        XCTAssertFalse(csv.contains(",exact"))
        XCTAssertTrue(HistoryExport.csv([record]).contains(",exact"))
    }

    func testCSVQuotesCarriageReturns() {
        XCTAssertEqual(HistoryExport.field("a\rb"), "\"a\rb\"")
    }

    func testScheduledMidnightResetsValuesAndPreservesOutgoingHistory() throws {
        let today = try XCTUnwrap(DayKey.date(from: "2026-09-08"))
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: today))
        let captured = UsageSnapshot(dayKey: DayKey.today(today), distractionMinutes: 32,
                                     messagesMinutes: 6, distractionsConfigured: true,
                                     messagesConfigured: true, monitoringIsActive: true,
                                     updatedAt: today.addingTimeInterval(3600))
        let reset = WidgetRefreshSchedule.snapshotForDisplay(
            captured, config: BudgetConfig(), accuracy: .lowerBound, now: tomorrow
        )
        XCTAssertEqual(reset.dayKey, DayKey.today(tomorrow))
        XCTAssertEqual(reset.distractionMinutes, 0)
        XCTAssertEqual(reset.messagesMinutes, 0)
        XCTAssertTrue(reset.isFloor)
        XCTAssertEqual(captured.distractionMinutes, 32)
        let history = WidgetRefreshSchedule.rolloverHistory(
            snapshot: captured, history: [], accuracy: .lowerBound
        )
        XCTAssertEqual(history.first?.distractionMinutes, 32)
        XCTAssertEqual(history.first?.isFloor, true)
        XCTAssertEqual(history.first?.dayKey, DayKey.today(today))
    }

    func testMacRolloverWaitsForActualNewDayTracking() throws {
        let today = try XCTUnwrap(DayKey.date(from: "2026-09-08"))
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: today))
        let captured = UsageSnapshot(dayKey: DayKey.today(today), distractionMinutes: 18,
                                     distractionsConfigured: true, monitoringIsActive: true,
                                     updatedAt: tomorrow.addingTimeInterval(-10))
        let reset = WidgetRefreshSchedule.snapshotForDisplay(
            captured, config: BudgetConfig(), accuracy: .exact, now: tomorrow
        )
        XCTAssertEqual(reset.distractionMinutes, 0)
        XCTAssertFalse(reset.monitoringIsActive)
        XCTAssertFalse(reset.isFloor)
    }

    func testFloorDoesNotProveAnUnderBudgetRun() {
        let floor = DayRecord(dayKey: "2026-09-07", distractionMinutes: 18,
                              messagesMinutes: 0, distractionBudgetMinutes: 45,
                              messagesBudgetMinutes: 60, isFloor: true)
        let result = StreakStats.distractions(records: [floor], snapshot: UsageSnapshot(), today: "2026-09-08")
        XCTAssertEqual(result.underBudgetDays, 0)
        XCTAssertEqual(result.underBudgetRun, 0)
        XCTAssertEqual(result.totalDays, 0)
    }

    func testMissingDayBreaksAnExactRun() {
        let records = ["2026-09-05", "2026-09-07"].map {
            DayRecord(dayKey: $0, distractionMinutes: 18, messagesMinutes: 0,
                      distractionBudgetMinutes: 45, messagesBudgetMinutes: 60, isFloor: false)
        }
        let result = StreakStats.distractions(records: records, snapshot: UsageSnapshot(), today: "2026-09-08")
        XCTAssertEqual(result.underBudgetRun, 1)
    }

    func testExactTargetIsReachedNotExceededInSpokenSummary() {
        let snapshot = UsageSnapshot(distractionMinutes: 45, distractionBudgetMinutes: 45,
                                     distractionsConfigured: true, monitoringIsActive: true)
        let presentation = WidgetLedgerPresentation(snapshot: snapshot, ledger: .distractions, accuracy: .exact)
        XCTAssertTrue(presentation.spokenSummary.contains("reached"))
        XCTAssertFalse(presentation.spokenSummary.contains("past"))
    }

    func testEmptyMacHistoryDoesNotClaimTargetWasNeverReached() {
        let summary = WidgetWeekSummary(snapshot: UsageSnapshot(), history: [],
                                        ledger: .distractions, accuracy: .exact)
        XCTAssertEqual(summary.summaryText, "No recorded days")
    }
}
