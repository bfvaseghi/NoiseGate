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

        // Escalating overtime nags past 100% (only reachable while unblocked —
        // a shielded app can't accumulate more usage).
        if percent > 100 {
            let over = percent - 100
            if kind == "noise" {
                let bodies: [Int: String] = [
                    110: "10% past your noise budget. That word doesn't mean what you think it means.",
                    125: "A quarter over budget. Put. It. Down.",
                    150: "That's 1.5× your noise budget. This is an intervention.",
                    200: "DOUBLE your noise budget. NoiseGate is officially judging you."
                ]
                notify(id: "noise.\(percent)", title: "⛔️ \(over)% OVER on noise",
                       body: bodies[percent] ?? "You're \(over)% over your noise budget.",
                       critical: true)
            } else {
                notify(id: "msg.\(percent)", title: "💬 \(over)% over on messages",
                       body: "You're \(over)% past your messaging budget. Still not blocking you — but come on.",
                       critical: true)
            }
            return
        }

        // Nudges at 50 / 80 / 100.
        guard BudgetConfig.nudgePercents.contains(percent) else { return }
        if kind == "noise" {
            switch percent {
            case 50:
                notify(id: "noise.50", title: "⚠️ HALF the noise budget — gone",
                       body: "That's half of \(config.noiseBudgetMinutes.asHoursMinutes) on apps you yourself called worthless. Worth it?")
            case 80:
                notify(id: "noise.80", title: "🚨 80% burned",
                       body: "About \(max(1, config.noiseBudgetMinutes / 5).asHoursMinutes) of noise left. Land the plane NOW.",
                       critical: true)
            case 100:
                if config.blockNoiseAtBudget {
                    ShieldController.add(.budget)
                    notify(id: "noise.100", title: "⛔️ DONE. Noise is BLOCKED.",
                           body: "Budget spent. The wall is up until midnight. Go be a person.",
                           critical: true)
                } else {
                    notify(id: "noise.100", title: "⛔️ Noise budget SPENT",
                           body: "Past \(config.noiseBudgetMinutes.asHoursMinutes) of noise today. Blocking is off — that was your call.",
                           critical: true)
                }
            default:
                break
            }
        } else if kind == "msg" {
            switch percent {
            case 50:
                notify(id: "msg.50", title: "💬 Messages: halfway",
                       body: "Half of today's messaging budget used.")
            case 80:
                notify(id: "msg.80", title: "💬 Messages at 80%",
                       body: "You've been in messages a while. Just call them.")
            case 100:
                notify(id: "msg.100", title: "💬 Messages budget SPENT",
                       body: "Over \(config.messagesBudgetMinutes.asHoursMinutes) of messaging today. Never blocked — but you said you wanted to know.",
                       critical: true)
            default:
                break
            }
        }
    }

    /// `critical` bumps the interruption level to time-sensitive so the nudge
    /// punches through scheduled summaries and most Focus modes.
    private func notify(id: String, title: String, body: String, critical: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = critical ? .timeSensitive : .active
        let request = UNNotificationRequest(
            identifier: "noisegate.\(id).\(DayKey.today())",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
