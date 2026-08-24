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
}
