import Foundation

/// The single source of notification copy, shared by the iOS monitor
/// extension and the macOS tracker so the two platforms never drift.
/// Tone is neutral and factual: state the numbers, note that nothing is
/// blocked, and stop.
enum NudgeText {
    /// Copy for a budget-threshold crossing, or nil for percents that
    /// update progress but don't notify.
    static func notification(
        kind: String, percent: Int, budgetMinutes: Int
    ) -> (title: String, body: String)? {
        let category = kind == "noise" ? "Noise" : "Messages"
        switch percent {
        case 50:
            return ("\(category): 50% of budget used",
                    "\((budgetMinutes / 2).asHoursMinutes) of today's \(budgetMinutes.asHoursMinutes) budget used.")
        case 80:
            return ("\(category): 80% of budget used",
                    "About \(max(1, budgetMinutes / 5).asHoursMinutes) remaining today.")
        case 100:
            return ("\(category): budget reached",
                    "\(budgetMinutes.asHoursMinutes) used today. Nothing is blocked.")
        case 150, 200:
            return ("\(category): \(percent)% of budget",
                    "Usage today is \(percent)% of the \(budgetMinutes.asHoursMinutes) budget.")
        default:
            return nil
        }
    }
}
