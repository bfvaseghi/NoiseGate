import Foundation

/// Applies one validated DeviceActivity threshold to the widget feed. Keeping
/// this reducer outside the extension makes midnight and ledger-preservation
/// behavior testable in the host target.
enum ThresholdSnapshotReducer {
    @discardableResult
    static func apply(
        to snapshot: inout UsageSnapshot,
        today: String,
        kind: String,
        budgetMinutes: Int,
        thresholdMinutes: Int,
        fallbackConfig: BudgetConfig,
        now: Date = Date()
    ) -> Bool {
        guard kind == "distractions" || kind == "msg" else { return false }

        if snapshot.dayKey != today {
            let distractionsConfigured = snapshot.distractionsConfigured
            let messagesConfigured = snapshot.messagesConfigured
            snapshot = UsageSnapshot(
                dayKey: today,
                distractionBudgetMinutes: fallbackConfig.distractionBudgetMinutes,
                messagesBudgetMinutes: fallbackConfig.messagesBudgetMinutes,
                distractionsConfigured: distractionsConfigured,
                messagesConfigured: messagesConfigured,
                isFloor: true,
                monitoringIsActive: true
            )
        }

        if kind == "distractions" {
            snapshot.distractionsConfigured = true
            snapshot.distractionBudgetMinutes = budgetMinutes
            snapshot.distractionMinutes = max(
                snapshot.distractionMinutes,
                thresholdMinutes
            )
        } else {
            snapshot.messagesConfigured = true
            snapshot.messagesBudgetMinutes = budgetMinutes
            snapshot.messagesMinutes = max(snapshot.messagesMinutes, thresholdMinutes)
        }
        snapshot.isFloor = true
        snapshot.monitoringIsActive = true
        snapshot.updatedAt = now
        return true
    }
}
