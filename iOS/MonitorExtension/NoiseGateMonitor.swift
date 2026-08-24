import DeviceActivity
import ManagedSettings
import UserNotifications
import WidgetKit
import Foundation

/// Runs in the background, woken by the system when a DeviceActivity interval
/// starts/ends or a usage threshold is crossed. This is where budgets turn
/// into nudges and shields.
class NoiseGateMonitor: DeviceActivityMonitor {

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        switch activity.rawValue {
        case "daily":
            // A new day: reset the widget snapshot and lift any budget shield.
            let config = BudgetConfig.load()
            var snap = UsageSnapshot()
            snap.noiseBudgetMinutes = config.noiseBudgetMinutes
            snap.messagesBudgetMinutes = config.messagesBudgetMinutes
            snap.isFloor = true
            snap.focusActive = ShieldController.activeReasons().contains(.focus)
            snap.save()
            ShieldController.remove(.budget)
            WidgetCenter.shared.reloadAllTimelines()
        case "quietHours":
            ShieldController.add(.quiet)
            notify(id: "quiet.start",
                   title: "Quiet hours 🌙",
                   body: "Noise apps are off the table until morning.")
        default:
            break
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity.rawValue == "quietHours" {
            ShieldController.remove(.quiet)
        }
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

        // Nudges at 50 / 80 / 100.
        guard BudgetConfig.nudgePercents.contains(percent) else { return }
        if kind == "noise" {
            switch percent {
            case 50:
                notify(id: "noise.50", title: "Halfway through the noise 📉",
                       body: "You've used half of today's noise budget (\(config.noiseBudgetMinutes.asHoursMinutes)). Worth it so far?")
            case 80:
                notify(id: "noise.80", title: "80% of the noise budget gone",
                       body: "About \(max(1, config.noiseBudgetMinutes / 5).asHoursMinutes) left. Land the plane.")
            case 100:
                if config.blockNoiseAtBudget {
                    ShieldController.add(.budget)
                    notify(id: "noise.100", title: "Noise budget spent 🔇",
                           body: "That's the lot — noise apps are blocked until tomorrow.")
                } else {
                    notify(id: "noise.100", title: "Noise budget spent",
                           body: "You're past \(config.noiseBudgetMinutes.asHoursMinutes) of noise today. Blocking is off, so this is just a nudge.")
                }
            default:
                break
            }
        } else if kind == "msg" {
            switch percent {
            case 50:
                notify(id: "msg.50", title: "Messages check-in 💬",
                       body: "Half of today's messaging budget used.")
            case 80:
                notify(id: "msg.80", title: "Messages at 80%",
                       body: "You've been in messages a while. Maybe just call them?")
            case 100:
                notify(id: "msg.100", title: "Messages budget spent",
                       body: "Over \(config.messagesBudgetMinutes.asHoursMinutes) of messaging today. Not blocked — just so you know.")
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
