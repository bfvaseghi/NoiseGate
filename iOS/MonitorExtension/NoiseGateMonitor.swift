import DeviceActivity
import UserNotifications
import WidgetKit
import Foundation

/// Runs in the background, woken by the system when the daily interval starts
/// or a usage threshold is crossed. NoiseGate never blocks anything — this is
/// purely awareness: update the widget, and check in with a friendly note at
/// the budget milestones.
class NoiseGateMonitor: DeviceActivityMonitor {

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard activity.rawValue == "daily" else { return }
        // A new day: reset the widget snapshot.
        let config = BudgetConfig.load()
        var snap = UsageSnapshot()
        snap.noiseBudgetMinutes = config.noiseBudgetMinutes
        snap.messagesBudgetMinutes = config.messagesBudgetMinutes
        snap.isFloor = true
        snap.save()
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

        // Update the widget's floor estimate: crossing "noise.p80" means at
        // least 80% of the noise budget has been spent.
        var snap = UsageSnapshot.loadToday()
        if kind == "noise" {
            snap.noiseMinutes = max(snap.noiseMinutes, config.noiseBudgetMinutes * percent / 100)
        } else if kind == "msg" {
            snap.messagesMinutes = max(snap.messagesMinutes, config.messagesBudgetMinutes * percent / 100)
        }
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()

        // Gentle check-ins past 100%.
        if percent > 100 {
            if kind == "noise" {
                notify(id: "noise.\(percent)",
                       title: percent >= 200 ? "Noise check-in" : "Still scrolling?",
                       body: percent >= 200
                        ? "You're at double your usual noise line today. No judgment — just flagging it."
                        : "You're about 50% past your noise line for today. Maybe a good stopping point?")
            } else {
                notify(id: "msg.\(percent)",
                       title: "Messages check-in",
                       body: percent >= 200
                        ? "Messaging is at double your usual line today."
                        : "You're well past your usual messaging time today. Might be a call by now?")
            }
            return
        }

        // Nudges at 50 / 80 / 100.
        guard BudgetConfig.nudgePercents.contains(percent) else { return }
        if kind == "noise" {
            switch percent {
            case 50:
                notify(id: "noise.50", title: "Halfway there",
                       body: "You've used half of today's noise budget (\(config.noiseBudgetMinutes.asHoursMinutes)). Just so you know.")
            case 80:
                notify(id: "noise.80", title: "80% of your noise budget used",
                       body: "About \(max(1, config.noiseBudgetMinutes / 5).asHoursMinutes) left today, if you're keeping score.")
            case 100:
                notify(id: "noise.100", title: "That's today's noise budget",
                       body: "You've hit \(config.noiseBudgetMinutes.asHoursMinutes). Nothing gets blocked — this is just your line in the sand.")
            default:
                break
            }
        } else if kind == "msg" {
            switch percent {
            case 50:
                notify(id: "msg.50", title: "Messages: halfway",
                       body: "Half of today's messaging budget used.")
            case 80:
                notify(id: "msg.80", title: "Messages at 80%",
                       body: "You've been in messages a while today.")
            case 100:
                notify(id: "msg.100", title: "That's your Messages budget",
                       body: "Over \(config.messagesBudgetMinutes.asHoursMinutes) of messaging today. Maybe wrap up the thread?")
            default:
                break
            }
        }
    }

    private func notify(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "noisegate.\(id).\(DayKey.today())",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
