import DeviceActivity
import UserNotifications
import WidgetKit
import Foundation

/// Runs in the background, woken by the system when the daily interval starts
/// or a usage threshold is crossed. NoiseGate never blocks anything — this
/// extension only updates the widget snapshot and posts a factual
/// notification at each budget milestone (once per day each).
class NoiseGateMonitor: DeviceActivityMonitor {

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard activity.rawValue == "daily" else { return }

        // File the finished day into history before resetting. Read the raw
        // stored snapshot — loadToday() would already have reset it.
        if let previous = AppGroup.defaults.codable(UsageSnapshot.self, forKey: StoreKey.usageSnapshot),
           previous.dayKey != DayKey.today() {
            HistoryStore.record(DayRecord(
                dayKey: previous.dayKey,
                noiseMinutes: previous.noiseMinutes,
                messagesMinutes: previous.messagesMinutes,
                noiseBudgetMinutes: previous.noiseBudgetMinutes,
                messagesBudgetMinutes: previous.messagesBudgetMinutes,
                isFloor: true
            ))
        }

        // A new day: reset the widget snapshot and the nudge ledger.
        let config = BudgetConfig.load()
        var snap = UsageSnapshot()
        snap.noiseBudgetMinutes = config.noiseBudgetMinutes
        snap.messagesBudgetMinutes = config.messagesBudgetMinutes
        snap.isFloor = true
        snap.save()
        AppGroup.defaults.set([String](), forKey: StoreKey.iosNudgesSent)
        WidgetCenter.shared.reloadAllTimelines()
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        let parts = event.rawValue.components(separatedBy: ".p")
        guard parts.count == 2, let percent = Int(parts[1]) else { return }
        let kind = parts[0]
        let config = BudgetConfig.load()
        let budget = kind == "noise" ? config.noiseBudgetMinutes : config.messagesBudgetMinutes

        // Update the widget's floor estimate: crossing "noise.p80" means at
        // least 80% of the noise budget has been spent.
        var snap = UsageSnapshot.loadToday()
        if kind == "noise" {
            snap.noiseMinutes = max(snap.noiseMinutes, budget * percent / 100)
        } else if kind == "msg" {
            snap.messagesMinutes = max(snap.messagesMinutes, budget * percent / 100)
        }
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()

        guard config.notifies(atPercent: percent),
              let text = NudgeText.notification(kind: kind, percent: percent,
                                                budgetMinutes: budget) else { return }

        // Once per day per milestone, even if a mid-day monitoring restart
        // (settings or toggle change) makes a threshold fire again.
        let key = "\(kind).\(percent)@\(DayKey.today())"
        var sent = AppGroup.defaults.stringArray(forKey: StoreKey.iosNudgesSent) ?? []
        guard !sent.contains(key) else { return }
        sent.append(key)
        AppGroup.defaults.set(sent, forKey: StoreKey.iosNudgesSent)

        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "noisegate.\(key)", content: content, trigger: nil)
        )
    }
}
