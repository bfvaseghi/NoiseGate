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
        let category = kind == "distractions" || kind == "noise"
            ? "Distractions" : "Messages"
        let usedMinutes = max(
            1,
            Int((Double(budgetMinutes) * Double(percent) / 100).rounded(.up))
        )
        switch percent {
        case 50:
            return ("\(category): 50% checkpoint",
                    "At least \(usedMinutes.asHoursMinutes) used against today's \(budgetMinutes.asHoursMinutes) budget.")
        case 80:
            return ("\(category): 80% checkpoint",
                    "At least \(usedMinutes.asHoursMinutes) used against today's \(budgetMinutes.asHoursMinutes) budget.")
        case 100:
            return ("\(category): budget reached",
                    "At least \(budgetMinutes.asHoursMinutes) used today. Nothing is blocked.")
        case 150, 200:
            return ("\(category): \(percent)% of budget",
                    "At least \(usedMinutes.asHoursMinutes) used today against a \(budgetMinutes.asHoursMinutes) budget.")
        default:
            return nil
        }
    }
}
