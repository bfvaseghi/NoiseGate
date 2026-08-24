import Foundation
import XCTest
@testable import NoiseGateMac

final class MacLedgerTests: XCTestCase {
    func testV1LedgerDecodesForClassificationMigration() throws {
        let data = Data(#"""
        {
          "dayKey": "2026-08-24",
          "seconds": {
            "com.example.feed": 125,
            "com.apple.MobileSMS": 65
          }
        }
        """#.utf8)

        let ledger = try JSONDecoder().decode(MacLedger.self, from: data)

        XCTAssertEqual(ledger.legacyUnclassifiedSeconds["com.example.feed"], 125)
        XCTAssertEqual(ledger.legacyUnclassifiedSeconds["com.apple.MobileSMS"], 65)
        XCTAssertEqual(ledger.distractionSeconds, 0)
        XCTAssertEqual(ledger.messagesSeconds, 0)
        XCTAssertTrue(ledger.wasLegacyFormat)
    }

    func testLedgerTotalsStayInTheirAccrualCategory() {
        var config = BudgetConfig()
        config.distractionBudgetMinutes = 30
        config.messagesBudgetMinutes = 45
        var ledger = MacLedger(config: config, dayKey: "2026-08-24")
        ledger.distractionSecondsByBundleID["com.example.app"] = 90
        ledger.messagesSecondsByBundleID["com.example.app"] = 30

        XCTAssertEqual(ledger.distractionSeconds, 90)
        XCTAssertEqual(ledger.messagesSeconds, 30)
        XCTAssertEqual(ledger.dayRecord.distractionBudgetMinutes, 30)
        XCTAssertEqual(ledger.dayRecord.messagesBudgetMinutes, 45)
    }

    func testV1MigrationUsesPersistedTargetsAndMessagesWinsOverlap() throws {
        let data = Data(#"""
        {
          "dayKey": "2026-08-23",
          "seconds": {
            "com.example.feed": 125,
            "com.example.chat": 65,
            "com.example.unselected": 500
          }
        }
        """#.utf8)
        var ledger = try JSONDecoder().decode(MacLedger.self, from: data)
        var config = BudgetConfig()
        config.distractionBudgetMinutes = 35
        config.messagesBudgetMinutes = 75

        ledger.migrateLegacy(
            config: config,
            distractionBundleIDs: ["com.example.feed", "com.example.chat"],
            messagesBundleIDs: ["com.example.chat"]
        )

        XCTAssertEqual(ledger.distractionSeconds, 125)
        XCTAssertEqual(ledger.messagesSeconds, 65)
        XCTAssertEqual(ledger.distractionBudgetMinutes, 35)
        XCTAssertEqual(ledger.messagesBudgetMinutes, 75)
        XCTAssertTrue(ledger.legacyUnclassifiedSeconds.isEmpty)
        XCTAssertFalse(ledger.wasLegacyFormat)
    }

    func testMacSelectionsRoundTripAsOneValue() throws {
        let selections = MacSelections(
            distractions: ["com.example.feed"],
            messages: ["com.apple.iChat"]
        )

        let data = try JSONEncoder().encode(selections)
        let decoded = try JSONDecoder().decode(MacSelections.self, from: data)

        XCTAssertEqual(decoded, selections)
    }
}
