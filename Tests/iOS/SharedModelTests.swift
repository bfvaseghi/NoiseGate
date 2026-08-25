import DeviceActivity
import Foundation
import XCTest
@testable import NoiseGate

final class SharedModelTests: XCTestCase {
    func testLegacyBudgetConfigPreservesExistingValues() throws {
        let data = Data(#"""
        {
          "noiseBudgetMinutes": 35,
          "messagesBudgetMinutes": 70,
          "notifyAt": [50, 100],
          "overtimeNotifications": false
        }
        """#.utf8)

        let value = try JSONDecoder().decode(BudgetConfig.self, from: data)

        XCTAssertEqual(value.distractionBudgetMinutes, 35)
        XCTAssertEqual(value.messagesBudgetMinutes, 70)
        XCTAssertEqual(value.notifyAt, [50, 100])
        XCTAssertFalse(value.overtimeNotifications)
    }

    func testLegacySnapshotMigratesWithoutLosingToday() throws {
        let data = Data(#"""
        {
          "dayKey": "2026-08-24",
          "noiseMinutes": 31,
          "messagesMinutes": 12,
          "noiseBudgetMinutes": 45,
          "messagesBudgetMinutes": 60,
          "isFloor": true
        }
        """#.utf8)

        let value = try JSONDecoder().decode(UsageSnapshot.self, from: data)

        XCTAssertEqual(value.distractionMinutes, 31)
        XCTAssertEqual(value.messagesMinutes, 12)
        XCTAssertEqual(value.distractionBudgetMinutes, 45)
        XCTAssertTrue(value.isFloor)
        XCTAssertFalse(value.distractionsConfigured)
        XCTAssertFalse(value.messagesConfigured)
    }

    func testLegacyHistoryRecordMigratesWithoutChangingTarget() throws {
        let data = Data(#"""
        {
          "dayKey": "2026-08-23",
          "noiseMinutes": 46,
          "messagesMinutes": 20,
          "noiseBudgetMinutes": 45,
          "messagesBudgetMinutes": 60,
          "isFloor": true
        }
        """#.utf8)

        let value = try JSONDecoder().decode(DayRecord.self, from: data)

        XCTAssertEqual(value.distractionMinutes, 46)
        XCTAssertEqual(value.distractionBudgetMinutes, 45)
        XCTAssertTrue(value.distractionReachedBudget)
    }

    func testSharedStoreReadModifyWriteIsThreadAtomic() {
        let suite = "NoiseGateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(suite).lock")
        let store = SharedStore(defaults: defaults, lockFileURL: lockURL)

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            _ = store.update(Int.self, forKey: "counter", default: 0) { $0 += 1 }
        }

        XCTAssertEqual(store.load(Int.self, forKey: "counter"), 100)
        try? FileManager.default.removeItem(at: lockURL)
    }

    func testFinishedSnapshotKeepsItsHistoricalBudget() {
        let snapshot = UsageSnapshot(
            dayKey: "2026-08-23",
            distractionMinutes: 41,
            messagesMinutes: 17,
            distractionBudgetMinutes: 35,
            messagesBudgetMinutes: 55,
            isFloor: true
        )
        let record = DayRecord(snapshot: snapshot)

        XCTAssertEqual(record.distractionBudgetMinutes, 35)
        XCTAssertEqual(record.messagesBudgetMinutes, 55)
        XCTAssertTrue(record.distractionReachedBudget)
    }

    func testThresholdEventPinsGenerationBudgetAndExactFloor() throws {
        let name = ThresholdEvent.name(
            kind: "distractions",
            percent: 80,
            generation: 7,
            budgetMinutes: 45
        )

        let parsed = try XCTUnwrap(ThresholdEvent.parse(name))

        XCTAssertEqual(parsed.generation, 7)
        XCTAssertEqual(parsed.kind, "distractions")
        XCTAssertEqual(parsed.percent, 80)
        XCTAssertEqual(parsed.budgetMinutes, 45)
        XCTAssertEqual(parsed.thresholdMinutes, 36)
    }

    func testLegacyOrInconsistentThresholdEventsAreRejected() {
        XCTAssertNil(ThresholdEvent.parse(DeviceActivityEvent.Name("noise.p80")))
        XCTAssertNil(ThresholdEvent.parse(
            DeviceActivityEvent.Name("v3.g7.distractions.b45.m35.p80")
        ))
    }

    func testSnapshotConfigurationFlagsRoundTrip() throws {
        let snapshot = UsageSnapshot(
            distractionsConfigured: true,
            messagesConfigured: false,
            isFloor: true
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)

        XCTAssertTrue(decoded.distractionsConfigured)
        XCTAssertFalse(decoded.messagesConfigured)
        XCTAssertEqual(decoded, snapshot)
    }

    func testHistoryCanonicalizationRejectsBadDaysAndKeepsNewestDuplicate() {
        let older = DayRecord(
            dayKey: "2026-08-23",
            distractionMinutes: 10,
            messagesMinutes: 4,
            distractionBudgetMinutes: 45,
            messagesBudgetMinutes: 60,
            isFloor: true
        )
        var newer = older
        newer.distractionMinutes = 25
        let invalid = DayRecord(
            dayKey: "not-a-day",
            distractionMinutes: 99,
            messagesMinutes: 99,
            distractionBudgetMinutes: 45,
            messagesBudgetMinutes: 60,
            isFloor: true
        )

        let result = HistoryStore.canonicalized([older, invalid, newer])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.dayKey, "2026-08-23")
        XCTAssertEqual(result.first?.distractionMinutes, 25)
    }

    func testIOSWidgetPresentationForcesLowerBoundForLegacySnapshot() {
        let snapshot = UsageSnapshot(
            distractionMinutes: 36,
            distractionBudgetMinutes: 45,
            distractionsConfigured: true,
            isFloor: false,
            monitoringIsActive: true
        )

        let presentation = WidgetLedgerPresentation(
            snapshot: snapshot,
            ledger: .distractions,
            accuracy: .lowerBound
        )

        XCTAssertEqual(presentation.valueText, "≥36m")
        XCTAssertEqual(presentation.progressPercent, 80)
        XCTAssertEqual(presentation.signalText, "At least 80% of budget")
        XCTAssertTrue(presentation.accessibilityValue.hasPrefix("At least 36 minutes"))
    }

    func testFloorZeroSaysNoCheckpointInsteadOfZero() {
        let snapshot = UsageSnapshot(
            distractionMinutes: 0,
            distractionBudgetMinutes: 45,
            distractionsConfigured: true,
            isFloor: true,
            monitoringIsActive: true
        )
        let presentation = WidgetLedgerPresentation(
            snapshot: snapshot,
            ledger: .distractions,
            accuracy: .lowerBound
        )

        XCTAssertEqual(presentation.level, .waitingForCheckpoint)
        XCTAssertEqual(presentation.valueText, "—")
        XCTAssertEqual(presentation.valueAndBudgetText, "No checkpoint yet")
        XCTAssertEqual(presentation.signalText, "No checkpoint yet")
        XCTAssertFalse(presentation.signalText.localizedCaseInsensitiveContains("below"))
    }

    func testExactPresentationUsesExactCopyAndZero() {
        let snapshot = UsageSnapshot(
            distractionMinutes: 0,
            distractionBudgetMinutes: 45,
            distractionsConfigured: true,
            isFloor: true,
            monitoringIsActive: true
        )
        let presentation = WidgetLedgerPresentation(
            snapshot: snapshot,
            ledger: .distractions,
            accuracy: .exact
        )

        XCTAssertEqual(presentation.level, .clear)
        XCTAssertEqual(presentation.valueText, "0m")
        XCTAssertEqual(presentation.signalText, "0% of budget")
        XCTAssertFalse(presentation.accessibilityValue.contains("At least"))
    }

    func testPresentationFractionsClampAndExtremeMinutesDoNotOverflow() {
        let snapshot = UsageSnapshot(
            distractionMinutes: Int.max,
            distractionBudgetMinutes: 5,
            distractionsConfigured: true,
            monitoringIsActive: true
        )
        let exact = WidgetLedgerPresentation(
            snapshot: snapshot,
            ledger: .distractions,
            accuracy: .exact
        )
        let floor = WidgetLedgerPresentation(
            snapshot: snapshot,
            ledger: .distractions,
            accuracy: .lowerBound
        )

        XCTAssertEqual(exact.fraction, 1)
        XCTAssertEqual(exact.progressPercent, 100)
        XCTAssertEqual(floor.progressPercent, 200)
        XCTAssertEqual(exact.level, .over)
    }

    func testPresentationHandlesExtremePersistedBudget() {
        let snapshot = UsageSnapshot(
            distractionMinutes: Int.max,
            distractionBudgetMinutes: Int.max,
            distractionsConfigured: true,
            monitoringIsActive: true
        )
        let presentation = WidgetLedgerPresentation(
            snapshot: snapshot,
            ledger: .distractions,
            accuracy: .lowerBound
        )

        XCTAssertEqual(presentation.fraction, 1)
        XCTAssertEqual(presentation.progressPercent, 100)
        XCTAssertEqual(presentation.level, .reached)
    }

    func testMessagesPresentationUsesItsOwnBudgetAndState() {
        let snapshot = UsageSnapshot(
            distractionMinutes: 0,
            messagesMinutes: 60,
            distractionBudgetMinutes: 45,
            messagesBudgetMinutes: 60,
            distractionsConfigured: false,
            messagesConfigured: true,
            isFloor: true,
            monitoringIsActive: true
        )
        let messages = WidgetLedgerPresentation(
            snapshot: snapshot,
            ledger: .messages,
            accuracy: .lowerBound
        )

        XCTAssertEqual(messages.level, .reached)
        XCTAssertEqual(messages.valueText, "≥1h 00m")
        XCTAssertEqual(messages.signalText, "Budget crossed")
    }

    func testThresholdReducerPreservesOtherLedgerAcrossMidnight() {
        var config = BudgetConfig()
        config.distractionBudgetMinutes = 45
        config.messagesBudgetMinutes = 60
        let updateTime = Date(timeIntervalSince1970: 1_777_000_000)
        var snapshot = UsageSnapshot(
            dayKey: "2026-08-23",
            distractionMinutes: 45,
            messagesMinutes: 20,
            distractionBudgetMinutes: 45,
            messagesBudgetMinutes: 60,
            distractionsConfigured: true,
            messagesConfigured: true,
            isFloor: true,
            monitoringIsActive: false
        )

        XCTAssertTrue(ThresholdSnapshotReducer.apply(
            to: &snapshot,
            today: "2026-08-24",
            kind: "msg",
            budgetMinutes: 60,
            thresholdMinutes: 6,
            fallbackConfig: config,
            now: updateTime
        ))

        XCTAssertEqual(snapshot.dayKey, "2026-08-24")
        XCTAssertTrue(snapshot.distractionsConfigured)
        XCTAssertTrue(snapshot.messagesConfigured)
        XCTAssertEqual(snapshot.distractionMinutes, 0)
        XCTAssertEqual(snapshot.messagesMinutes, 6)
        XCTAssertEqual(snapshot.updatedAt, updateTime)
    }

    func testThresholdReducerIsMonotonicAndUsesEventBudget() {
        var config = BudgetConfig()
        config.distractionBudgetMinutes = 90
        var snapshot = UsageSnapshot(
            dayKey: "2026-08-24",
            distractionMinutes: 36,
            distractionBudgetMinutes: 45,
            distractionsConfigured: true,
            isFloor: true,
            monitoringIsActive: true
        )

        ThresholdSnapshotReducer.apply(
            to: &snapshot,
            today: "2026-08-24",
            kind: "distractions",
            budgetMinutes: 45,
            thresholdMinutes: 23,
            fallbackConfig: config
        )

        XCTAssertEqual(snapshot.distractionMinutes, 36)
        XCTAssertEqual(snapshot.distractionBudgetMinutes, 45)
        XCTAssertFalse(ThresholdSnapshotReducer.apply(
            to: &snapshot,
            today: "2026-08-24",
            kind: "unknown",
            budgetMinutes: 45,
            thresholdMinutes: 45,
            fallbackConfig: config
        ))
    }

    func testThresholdReducerLeavesUntouchedLedgerAndRejectsUnknownKind() {
        var config = BudgetConfig()
        var snapshot = UsageSnapshot(
            dayKey: "2026-08-24",
            distractionMinutes: 10,
            messagesMinutes: 44,
            distractionBudgetMinutes: 45,
            messagesBudgetMinutes: 75,
            distractionsConfigured: true,
            messagesConfigured: true,
            isFloor: true,
            monitoringIsActive: true
        )

        ThresholdSnapshotReducer.apply(
            to: &snapshot,
            today: "2026-08-24",
            kind: "distractions",
            budgetMinutes: 45,
            thresholdMinutes: 23,
            fallbackConfig: config
        )
        XCTAssertEqual(snapshot.messagesMinutes, 44)
        XCTAssertEqual(snapshot.messagesBudgetMinutes, 75)
        XCTAssertTrue(snapshot.messagesConfigured)

        let beforeInvalid = snapshot
        XCTAssertFalse(ThresholdSnapshotReducer.apply(
            to: &snapshot,
            today: "2026-08-24",
            kind: "messages",
            budgetMinutes: 60,
            thresholdMinutes: 30,
            fallbackConfig: config
        ))
        XCTAssertEqual(snapshot, beforeInvalid)
    }

    func testEveryAllowedThresholdRoundTripsAndRoundsUp() throws {
        let percents = BudgetConfig.progressPercents + BudgetConfig.overtimePercents
        for kind in ["distractions", "msg"] {
            for budget in 5...480 {
                for percent in percents {
                    let name = ThresholdEvent.name(
                        kind: kind,
                        percent: percent,
                        generation: 1,
                        budgetMinutes: budget
                    )
                    let parsed = try XCTUnwrap(ThresholdEvent.parse(name))
                    XCTAssertEqual(parsed.kind, kind)
                    XCTAssertEqual(parsed.thresholdMinutes, Int(
                        (Double(budget) * Double(percent) / 100).rounded(.up)
                    ))
                }
            }
        }
        XCTAssertEqual(ThresholdEvent.thresholdMinutes(budget: 45, percent: 10), 5)
        XCTAssertEqual(ThresholdEvent.thresholdMinutes(budget: 45, percent: 50), 23)
        XCTAssertEqual(ThresholdEvent.thresholdMinutes(budget: 45, percent: 150), 68)
        XCTAssertEqual(ThresholdEvent.thresholdMinutes(budget: 5, percent: 10), 1)
    }

    func testThresholdParserRejectsInvalidContractValues() {
        let invalid = [
            "v2.g1.distractions.b45.m23.p50",
            "v3.g0.distractions.b45.m23.p50",
            "v3.g1.unknown.b45.m23.p50",
            "v3.g1.distractions.b0.m1.p50",
            "v3.g1.distractions.b481.m241.p50",
            "v3.g1.distractions.b45.m23.p55",
            "v3.g1.distractions.b45.m22.p50"
        ]
        for value in invalid {
            XCTAssertNil(
                ThresholdEvent.parse(DeviceActivityEvent.Name(value)),
                value
            )
        }
    }

    func testNoiseGateRoutesRoundTripAndRejectExtraURLComponents() throws {
        for route in NoiseGateRoute.allCases {
            XCTAssertEqual(NoiseGateRoute(url: route.url), route)
        }
        XCTAssertEqual(NoiseGateRoute.today.tab, .today)
        XCTAssertEqual(NoiseGateRoute.apps.tab, .tracking)
        XCTAssertEqual(NoiseGateRoute.budgets.tab, .budgets)

        let rejected = [
            "https://today",
            "noisegate://unknown",
            "noisegate://today/extra",
            "noisegate://today?source=widget",
            "noisegate://today#fragment",
            "noisegate://user@today",
            "noisegate://today:123"
        ]
        for value in rejected {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertNil(NoiseGateRoute(url: url), value)
        }
    }

    func testLowerBoundWeekReportsOnlyConfirmedCrossings() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 24,
            hour: 12
        )))
        let history = [
            DayRecord(
                dayKey: "2026-08-22",
                distractionMinutes: 36,
                messagesMinutes: 0,
                distractionBudgetMinutes: 45,
                messagesBudgetMinutes: 60,
                isFloor: false
            ),
            DayRecord(
                dayKey: "2026-08-23",
                distractionMinutes: 45,
                messagesMinutes: 0,
                distractionBudgetMinutes: 45,
                messagesBudgetMinutes: 60,
                isFloor: false
            )
        ]
        let snapshot = UsageSnapshot(
            dayKey: "2026-08-24",
            distractionMinutes: 0,
            distractionBudgetMinutes: 45,
            distractionsConfigured: true,
            isFloor: false,
            monitoringIsActive: true
        )

        let summary = WidgetWeekSummary(
            snapshot: snapshot,
            history: history,
            ledger: .distractions,
            accuracy: .lowerBound,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.days.count, 7)
        XCTAssertEqual(summary.days.first { $0.dayKey == "2026-08-22" }?.status, .checkpoint)
        XCTAssertEqual(summary.days.first { $0.dayKey == "2026-08-23" }?.status, .reached)
        XCTAssertEqual(summary.days.first { $0.dayKey == "2026-08-24" }?.status, .noCheckpoint)
        XCTAssertEqual(summary.reachedDayCount, 1)
        XCTAssertEqual(summary.summaryText, "1 confirmed crossing")
        XCTAssertFalse(summary.summaryText.localizedCaseInsensitiveContains("under"))
    }

    func testExactWeekDistinguishesZeroFromMissingRecord() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 24,
            hour: 12
        )))
        let snapshot = UsageSnapshot(
            dayKey: "2026-08-24",
            distractionMinutes: 0,
            distractionBudgetMinutes: 45,
            distractionsConfigured: true,
            monitoringIsActive: true
        )

        let summary = WidgetWeekSummary(
            snapshot: snapshot,
            history: [],
            ledger: .distractions,
            accuracy: .exact,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.days.last?.status, .zero)
        XCTAssertEqual(summary.days.first?.status, .noRecord)
    }

    func testWeekRemovesStoredTodayWhenLiveSnapshotIsStale() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 24,
            hour: 12
        )))
        let poisonedToday = DayRecord(
            dayKey: "2026-08-24",
            distractionMinutes: 90,
            messagesMinutes: 0,
            distractionBudgetMinutes: 45,
            messagesBudgetMinutes: 60,
            isFloor: true
        )
        let staleSnapshot = UsageSnapshot(
            dayKey: "2026-08-23",
            distractionMinutes: 45,
            distractionBudgetMinutes: 45,
            distractionsConfigured: true,
            isFloor: true,
            monitoringIsActive: true
        )

        let summary = WidgetWeekSummary(
            snapshot: staleSnapshot,
            history: [poisonedToday],
            ledger: .distractions,
            accuracy: .lowerBound,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.days.last?.dayKey, "2026-08-24")
        XCTAssertEqual(summary.days.last?.status, .noRecord)
        XCTAssertEqual(summary.reachedDayCount, 0)
    }

    func testWidgetRefreshSchedulesClampToMidnightAndHandleStaleness() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let late = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 8,
            hour: 23,
            minute: 55
        )))
        let midnight = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 9
        )))
        XCTAssertEqual(
            WidgetRefreshSchedule.iOSNextRefresh(now: late, calendar: calendar),
            midnight
        )

        let noon = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 8,
            hour: 12
        )))
        XCTAssertEqual(
            WidgetRefreshSchedule.iOSNextRefresh(now: noon, calendar: calendar)
                .timeIntervalSince(noon),
            15 * 60,
            accuracy: 0.1
        )

        let fresh = UsageSnapshot(
            distractionsConfigured: true,
            monitoringIsActive: true,
            updatedAt: noon.addingTimeInterval(-10)
        )
        XCTAssertTrue(WidgetRefreshSchedule.currentMacSnapshot(
            fresh,
            now: noon.addingTimeInterval(35)
        ).monitoringIsActive)
        XCTAssertFalse(WidgetRefreshSchedule.currentMacSnapshot(
            fresh,
            now: noon.addingTimeInterval(36)
        ).monitoringIsActive)
        XCTAssertEqual(
            WidgetRefreshSchedule.macNextRefresh(
                snapshot: fresh,
                now: noon,
                calendar: calendar
            ).timeIntervalSince(noon),
            36,
            accuracy: 0.1
        )

        var stale = fresh
        stale.monitoringIsActive = false
        XCTAssertEqual(
            WidgetRefreshSchedule.macNextRefresh(
                snapshot: stale,
                now: noon,
                calendar: calendar
            ).timeIntervalSince(noon),
            5 * 60,
            accuracy: 0.1
        )
        XCTAssertEqual(
            WidgetRefreshSchedule.macNextRefresh(
                snapshot: stale,
                now: late,
                calendar: calendar
            ),
            midnight
        )
    }

    // MARK: - Weekend budgets

    /// A config written before weekend budgets existed must keep its numbers
    /// and behave exactly as it did: one target, every day.
    func testConfigWithoutWeekendKeysStaysSingleBudget() throws {
        let data = Data(#"""
        {
          "distractionBudgetMinutes": 45,
          "messagesBudgetMinutes": 60
        }
        """#.utf8)

        let value = try JSONDecoder().decode(BudgetConfig.self, from: data)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        XCTAssertFalse(value.weekendBudgetsEnabled)
        XCTAssertEqual(value.weekendDistractionBudgetMinutes, 75)
        for day in 22...28 {
            let date = try XCTUnwrap(
                calendar.date(from: DateComponents(year: 2026, month: 8, day: day))
            )
            XCTAssertEqual(value.distractionBudget(on: date, calendar: calendar), 45)
        }
    }

    func testWeekendBudgetAppliesOnlyToWeekendDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var config = BudgetConfig()
        config.distractionBudgetMinutes = 45
        config.weekendDistractionBudgetMinutes = 75
        config.weekendBudgetsEnabled = true

        // 22 Aug 2026 is a Saturday, 23 Aug a Sunday, 24 Aug a Monday.
        func budget(day: Int) throws -> Int {
            let date = try XCTUnwrap(
                calendar.date(from: DateComponents(year: 2026, month: 8, day: day))
            )
            return config.distractionBudget(on: date, calendar: calendar)
        }
        XCTAssertEqual(try budget(day: 21), 45, "Friday keeps the weekday target")
        XCTAssertEqual(try budget(day: 22), 75, "Saturday takes the weekend target")
        XCTAssertEqual(try budget(day: 23), 75, "Sunday takes the weekend target")
        XCTAssertEqual(try budget(day: 24), 45, "Monday returns to the weekday target")

        // Messages deliberately has no weekend variant.
        let saturday = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 22))
        )
        XCTAssertEqual(config.budget(kind: "msg", on: saturday, calendar: calendar), 60)
        XCTAssertEqual(config.budget(kind: "distractions", on: saturday, calendar: calendar), 75)
    }

    func testWeekendBudgetIsIgnoredWhileDisabled() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var config = BudgetConfig()
        config.distractionBudgetMinutes = 45
        config.weekendDistractionBudgetMinutes = 200
        config.weekendBudgetsEnabled = false

        let saturday = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 22))
        )
        XCTAssertEqual(config.distractionBudget(on: saturday, calendar: calendar), 45)
    }

    func testWeekendBudgetSurvivesEncodeDecodeAndClamps() throws {
        var config = BudgetConfig()
        config.weekendBudgetsEnabled = true
        config.weekendDistractionBudgetMinutes = 900   // above the 480 ceiling
        config.normalize()
        XCTAssertEqual(config.weekendDistractionBudgetMinutes, 480)

        let round = try JSONDecoder().decode(
            BudgetConfig.self,
            from: try JSONEncoder().encode(config)
        )
        XCTAssertTrue(round.weekendBudgetsEnabled)
        XCTAssertEqual(round.weekendDistractionBudgetMinutes, 480)
    }

    // MARK: - Pauses that end on their own

    func testPauseDurationsResolveToTheRightMoment() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(
                year: 2026, month: 8, day: 25, hour: 16, minute: 20
            ))
        )

        // "Until tomorrow" means the next midnight, not 24 hours from now —
        // a pause taken at 11pm should not still be running tomorrow evening.
        XCTAssertEqual(
            PausedTokens.Duration.today.end(from: now, calendar: calendar),
            try XCTUnwrap(
                calendar.date(from: DateComponents(year: 2026, month: 8, day: 26))
            )
        )
        XCTAssertEqual(
            PausedTokens.Duration.week.end(from: now, calendar: calendar),
            try XCTUnwrap(
                calendar.date(from: DateComponents(
                    year: 2026, month: 9, day: 1, hour: 16, minute: 20
                ))
            )
        )
        XCTAssertNil(
            PausedTokens.Duration.indefinitely.end(from: now, calendar: calendar),
            "An indefinite pause must never grow an end date"
        )
    }

    func testLegacyPausedTokensDecodeAsIndefinite() throws {
        // v1 stored only the token sets. Those pauses must keep behaving the
        // way they always did: they stay until the owner lifts them.
        let data = Data(#"""
        { "applications": [], "webDomains": [] }
        """#.utf8)

        var value = try JSONDecoder().decode(PausedTokens.self, from: data)
        XCTAssertTrue(value.applicationExpiry.isEmpty)
        XCTAssertTrue(value.webDomainExpiry.isEmpty)
        XCTAssertFalse(
            value.expire(now: .distantFuture),
            "Nothing can expire when nothing carries an end date"
        )
    }

    // MARK: - CSV export

    private func record(
        _ day: String,
        distraction: Int,
        messages: Int,
        isFloor: Bool
    ) -> DayRecord {
        DayRecord(
            dayKey: day,
            distractionMinutes: distraction,
            messagesMinutes: messages,
            distractionBudgetMinutes: 45,
            messagesBudgetMinutes: 60,
            isFloor: isFloor
        )
    }

    func testCSVMarksEveryRowAsExactOrAFloor() {
        let csv = HistoryExport.csv([
            record("2026-08-24", distraction: 52, messages: 37, isFloor: true),
            record("2026-08-23", distraction: 31, messages: 12, isFloor: false),
        ])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)

        XCTAssertEqual(String(lines[0]), HistoryExport.header)
        // Oldest first, whatever order the caller passed them in.
        XCTAssertEqual(lines[1], "2026-08-23,31,45,12,60,exact")
        XCTAssertEqual(lines[2], "2026-08-24,52,45,37,60,at_least")
        XCTAssertTrue(csv.hasSuffix("\n"), "A CSV should end with a newline")
    }

    func testCSVCarriesThePerDayBudgetsRatherThanTodays() {
        // A weekend day judged against 75 must export 75, even though the
        // weekday target is 45. This is the whole reason DayRecord stores its
        // own budgets.
        var weekend = record("2026-08-22", distraction: 80, messages: 20, isFloor: true)
        weekend.distractionBudgetMinutes = 75
        let csv = HistoryExport.csv([weekend])
        XCTAssertTrue(
            csv.contains("2026-08-22,80,75,20,60,at_least"),
            "Expected the weekend budget in the row, got: \(csv)"
        )
    }

    func testCSVDropsInvalidDaysAndDeduplicates() {
        let csv = HistoryExport.csv([
            record("not-a-day", distraction: 5, messages: 5, isFloor: true),
            record("2026-08-24", distraction: 10, messages: 1, isFloor: true),
            record("2026-08-24", distraction: 52, messages: 37, isFloor: true),
        ])
        let rows = csv
            .split(separator: "\n")
            .dropFirst()
        XCTAssertEqual(rows.count, 1, "One valid day, deduplicated, got: \(csv)")
        XCTAssertEqual(rows.first, "2026-08-24,52,45,37,60,at_least")
    }

    func testCSVFieldQuotingFollowsRFC4180() {
        XCTAssertEqual(HistoryExport.field("plain"), "plain")
        XCTAssertEqual(HistoryExport.field("with,comma"), "\"with,comma\"")
        XCTAssertEqual(HistoryExport.field("say \"hi\""), "\"say \"\"hi\"\"\"")
    }
}
