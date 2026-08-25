import AppIntents
import Foundation

/// Which total a Shortcut is asking about.
enum LedgerChoice: String, CaseIterable, AppEnum {
    case combined
    case distractions
    case messages

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "NoiseGate total"
    )

    static var caseDisplayRepresentations: [LedgerChoice: DisplayRepresentation] = [
        .combined: "Everything tracked",
        .distractions: "Distractions",
        .messages: "Messages",
    ]
}

/// Answers today's tracked time without opening the app.
///
/// The numbers come from the widget snapshot, which on iPhone holds threshold
/// floors rather than exact usage — Apple keeps the precise figure inside the
/// report extension. The wording therefore says "at least" and means it,
/// using the same presentation layer the widget renders from so the two can
/// never disagree.
struct TodayUsageIntent: AppIntent {
    static var title: LocalizedStringResource = "Get today's tracked time"
    static var description = IntentDescription(
        """
        How long you have spent today on the apps NoiseGate counts. \
        Nothing is blocked; this only reports.
        """
    )
    /// Answering out loud is the whole point, so this must not launch the app.
    static var openAppWhenRun = false

    @Parameter(title: "Total", default: .combined)
    var ledger: LedgerChoice

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        let snapshot = UsageSnapshot.loadToday()
        let distractions = WidgetLedgerPresentation(
            snapshot: snapshot,
            ledger: .distractions,
            accuracy: .lowerBound
        )
        let messages = WidgetLedgerPresentation(
            snapshot: snapshot,
            ledger: .messages,
            accuracy: .lowerBound
        )

        switch ledger {
        case .distractions:
            return .result(
                value: distractions.minutes,
                dialog: IntentDialog(stringLiteral: distractions.spokenSummary)
            )
        case .messages:
            return .result(
                value: messages.minutes,
                dialog: IntentDialog(stringLiteral: messages.spokenSummary)
            )
        case .combined:
            let total = distractions.minutes + messages.minutes
            let budget = distractions.budgetMinutes + messages.budgetMinutes
            guard distractions.isConfigured || messages.isConfigured else {
                return .result(
                    value: 0,
                    dialog: "Nothing is selected to count yet."
                )
            }
            // Floors add up to a floor, so the combined answer stays hedged.
            let sentence = "At least \(total.asHoursMinutes) tracked today, "
                + "against a \(budget.asHoursMinutes) combined budget. "
                + "\(distractions.spokenSummary) \(messages.spokenSummary)"
            return .result(value: total, dialog: IntentDialog(stringLiteral: sentence))
        }
    }
}

/// Opens the app on a chosen tab, so a spoken "open my budgets" lands
/// somewhere useful rather than on whatever was last on screen.
struct OpenNoiseGateIntent: AppIntent {
    static var title: LocalizedStringResource = "Open NoiseGate"
    static var description = IntentDescription("Open NoiseGate on a chosen tab.")
    static var openAppWhenRun = true

    @Parameter(title: "Tab", default: .today)
    var tab: RouteChoice

    func perform() async throws -> some IntentResult {
        tab.route.requestOpen()
        return .result()
    }
}

/// Which tab an "open" Shortcut lands on.
enum RouteChoice: String, CaseIterable, AppEnum {
    case today
    case apps
    case budgets

    var route: NoiseGateRoute {
        switch self {
        case .today: return .today
        case .apps: return .apps
        case .budgets: return .budgets
        }
    }

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "NoiseGate tab")

    static var caseDisplayRepresentations: [RouteChoice: DisplayRepresentation] = [
        .today: "Today",
        .apps: "Apps",
        .budgets: "Budgets",
    ]
}

struct NoiseGateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TodayUsageIntent(),
            phrases: [
                "How much have I used in \(.applicationName)",
                "What does \(.applicationName) count today",
                "Check my \(.applicationName) total",
            ],
            shortTitle: "Today's tracked time",
            systemImageName: "chart.bar.fill"
        )
        AppShortcut(
            intent: OpenNoiseGateIntent(),
            phrases: ["Open \(.applicationName)"],
            shortTitle: "Open NoiseGate",
            systemImageName: "app.badge"
        )
    }
}
