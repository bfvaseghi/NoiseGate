import DeviceActivity
import Foundation
import UserNotifications
import WidgetKit

/// Background threshold handling. This extension never blocks. It only
/// advances truthful widget floors and posts enabled, once-per-day nudges.
final class NoiseGateMonitor: DeviceActivityMonitor {
    private let store = SharedStore.shared

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard activity.rawValue == DeviceActivityName.daily.rawValue else { return }
        guard store.bool(forKey: StoreKey.monitoringAcceptsCallbacks) else { return }

        // Read the raw stored value before replacing it with today's snapshot.
        let today = DayKey.today()
        let previous = store.load(UsageSnapshot.self, forKey: StoreKey.usageSnapshot)

        // DeviceActivity also calls this during a mid-day restart. Preserve
        // the existing floors and nudge ledger. Repair only the active flag in
        // case the host app exited after startMonitoring succeeded.
        if let previous, previous.dayKey == today {
            guard !previous.monitoringIsActive else { return }
            _ = store.update(
                UsageSnapshot.self,
                forKey: StoreKey.usageSnapshot,
                default: previous
            ) { snapshot in
                guard snapshot.dayKey == today else { return }
                snapshot.monitoringIsActive = true
                snapshot.updatedAt = .now
            }
            WidgetCenter.shared.reloadTimelines(ofKind: "NoiseGateWidget")
            return
        }
        if let previous {
            HistoryStore.recordFinishedSnapshot(previous)
        }

        let config = BudgetConfig.load()
        var snapshot = UsageSnapshot(
            dayKey: today,
            distractionsConfigured: previous?.distractionsConfigured ?? false,
            messagesConfigured: previous?.messagesConfigured ?? false,
            isFloor: true
        )
        let distractionBudget = config.distractionBudget(on: .now)
        snapshot.distractionBudgetMinutes = distractionBudget
        snapshot.messagesBudgetMinutes = config.messagesBudgetMinutes
        // Crossing into (or out of) a weekend changes which budget applies,
        // and the armed thresholds were built for yesterday's. Ask the host to
        // rebuild them; until it does, floors below stay truthful because a
        // crossed threshold is a fact about usage, not about the target.
        if let previous, previous.distractionBudgetMinutes != distractionBudget {
            store.saveBool(true, forKey: StoreKey.monitoringNeedsReconfigure)
        }
        snapshot.isFloor = true
        snapshot.monitoringIsActive = true
        snapshot.updatedAt = .now
        snapshot.save()
        store.saveStringArray([], forKey: StoreKey.iosNudgesSent)
        WidgetCenter.shared.reloadTimelines(ofKind: "NoiseGateWidget")
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        guard activity.rawValue == DeviceActivityName.daily.rawValue else { return }
        guard store.bool(forKey: StoreKey.monitoringAcceptsCallbacks),
              let parsed = ThresholdEvent.parse(event) else { return }
        guard parsed.generation == store.load(
            Int.self,
            forKey: StoreKey.monitoringGeneration
        ) else { return }
        let kind = parsed.kind
        let percent = parsed.percent
        let budget = parsed.budgetMinutes
        let thresholdMinutes = parsed.thresholdMinutes

        // Notification preferences may change without rebuilding monitoring.
        // The scheduled budget and threshold must come from the event itself.
        let config = BudgetConfig.load()
        let today = DayKey.today()

        // Defensive ordering: Apple normally starts the interval before
        // delivering its events, but filing here too prevents a stale snapshot
        // from being overwritten if callbacks arrive in another order.
        if let previous = store.load(UsageSnapshot.self, forKey: StoreKey.usageSnapshot) {
            HistoryStore.recordFinishedSnapshot(previous, today: today)
        }

        _ = store.update(
            UsageSnapshot.self,
            forKey: StoreKey.usageSnapshot,
            default: UsageSnapshot()
        ) { snapshot in
            ThresholdSnapshotReducer.apply(
                to: &snapshot,
                today: today,
                kind: kind,
                budgetMinutes: budget,
                thresholdMinutes: thresholdMinutes,
                fallbackConfig: config
            )
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "NoiseGateWidget")

        // A reconfiguration can make several includesPastActivity events fire
        // together. Rebuild the widget floor, but do not turn that catch-up
        // into a burst of stale notifications.
        if let configuredAt = store.load(Date.self, forKey: StoreKey.monitoringConfiguredAt) {
            let elapsed = Date().timeIntervalSince(configuredAt)
            if elapsed >= 0 && elapsed < 120 { return }
        }

        // An event armed for a different budget still proves the minutes
        // were spent, so its floor was applied above. Its percentage is not
        // today's percentage, though, so it must not be announced as one.
        guard budget == config.budget(kind: kind, on: .now) else { return }

        guard config.notifies(atPercent: percent),
              let text = NudgeText.notification(
                kind: kind,
                percent: percent,
                budgetMinutes: budget
              ) else { return }

        let key = "\(kind).\(percent)@\(today)"
        let legacyKey = kind == "distractions"
            ? "noise.\(percent)@\(today)" : nil
        var inserted = false
        _ = store.updateStringSet(forKey: StoreKey.iosNudgesSent) { sent in
            let legacyWasSent = legacyKey.map { sent.contains($0) } ?? false
            let wasSent = sent.contains(key) || legacyWasSent
            sent.insert(key)
            inserted = !wasSent
        }
        guard inserted else { return }

        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default
        content.threadIdentifier = "noisegate.\(kind)"
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "noisegate.\(key)",
                content: content,
                trigger: nil
            )
        )
    }
}
