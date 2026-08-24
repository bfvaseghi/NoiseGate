import AppIntents
import SwiftUI
import WidgetKit

@main
struct NoiseGateMacWidgetBundle: WidgetBundle {
    var body: some Widget {
        NoiseGateMacWidget()
    }
}

enum MacWidgetFocus: String, AppEnum {
    case automatic
    case distractions
    case messages

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Focus")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .automatic: "Automatic",
        .distractions: "Distractions",
        .messages: "Messages"
    ]
}

struct NoiseGateMacWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "NoiseGate focus"
    static var description = IntentDescription(
        "Choose which ledger the widget emphasizes."
    )

    @Parameter(title: "Focus", default: .automatic)
    var focus: MacWidgetFocus
}

struct MacSnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
    let history: [DayRecord]
    let focus: MacWidgetFocus

    var primaryLedger: WidgetLedger {
        switch focus {
        case .distractions:
            return .distractions
        case .messages:
            return .messages
        case .automatic:
            return snapshot.distractionsConfigured || !snapshot.messagesConfigured
                ? .distractions : .messages
        }
    }

    var secondaryLedger: WidgetLedger? {
        guard focus == .automatic else { return nil }
        return primaryLedger == .distractions ? .messages : .distractions
    }
}

struct MacSnapshotProvider: AppIntentTimelineProvider {
    private func currentSnapshot(now: Date = Date()) -> UsageSnapshot {
        WidgetRefreshSchedule.currentMacSnapshot(
            UsageSnapshot.loadToday(),
            now: now
        )
    }

    func placeholder(in context: Context) -> MacSnapshotEntry {
        sampleEntry(focus: .automatic, includeHistory: context.family == .systemLarge)
    }

    func snapshot(
        for configuration: NoiseGateMacWidgetIntent,
        in context: Context
    ) async -> MacSnapshotEntry {
        if context.isPreview {
            return sampleEntry(
                focus: configuration.focus,
                includeHistory: context.family == .systemLarge
            )
        }
        return makeEntry(
            focus: configuration.focus,
            includeHistory: context.family == .systemLarge
        )
    }

    func timeline(
        for configuration: NoiseGateMacWidgetIntent,
        in context: Context
    ) async -> Timeline<MacSnapshotEntry> {
        let now = Date()
        let includeHistory = context.family == .systemLarge
        let entry = makeEntry(focus: configuration.focus,
                              includeHistory: includeHistory,
                              now: now)
        var entries = [entry]

        // If the tracker stops heartbeating, show the paused state as a second
        // scheduled entry. Rendering it costs nothing, whereas asking WidgetKit
        // to reload at the staleness deadline would burn the refresh budget and
        // get the widget throttled.
        if let staleDate = WidgetRefreshSchedule.macStaleEntryDate(
            snapshot: entry.snapshot, now: now
        ) {
            entries.append(
                makeEntry(focus: configuration.focus,
                          includeHistory: includeHistory,
                          now: staleDate)
            )
        }

        let refresh = WidgetRefreshSchedule.macNextRefresh(
            snapshot: entry.snapshot,
            now: now
        )
        return Timeline(entries: entries, policy: .after(refresh))
    }

    private func makeEntry(
        focus: MacWidgetFocus,
        includeHistory: Bool,
        now: Date = Date()
    ) -> MacSnapshotEntry {
        MacSnapshotEntry(
            date: now,
            snapshot: currentSnapshot(now: now),
            history: includeHistory ? HistoryStore.load() : [],
            focus: focus
        )
    }

    private func sampleEntry(
        focus: MacWidgetFocus,
        includeHistory: Bool
    ) -> MacSnapshotEntry {
        MacSnapshotEntry(
            date: .now,
            snapshot: UsageSnapshot(
                distractionMinutes: 36,
                messagesMinutes: 20,
                distractionBudgetMinutes: 45,
                messagesBudgetMinutes: 60,
                distractionsConfigured: true,
                messagesConfigured: true,
                monitoringIsActive: true
            ),
            history: includeHistory ? Self.placeholderHistory : [],
            focus: focus
        )
    }

    private static var placeholderHistory: [DayRecord] {
        let calendar = Calendar.current
        let exampleMinutes = [18, 32, 45, 22, 51, 29]
        return (1...6).compactMap { daysAgo in
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: .now) else {
                return nil
            }
            let minutes = exampleMinutes[daysAgo - 1]
            return DayRecord(
                dayKey: DayKey.today(date),
                distractionMinutes: minutes,
                messagesMinutes: max(8, minutes / 2),
                distractionBudgetMinutes: 45,
                messagesBudgetMinutes: 60,
                isFloor: false
            )
        }
    }
}

struct NoiseGateMacWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "NoiseGateMacWidget",
            intent: NoiseGateMacWidgetIntent.self,
            provider: MacSnapshotProvider()
        ) { entry in
            MacWidgetView(entry: entry)
                .containerBackground(NG.paper, for: .widget)
        }
        .configurationDisplayName("NoiseGate")
        .description("Exact Distractions and Messages tracked on this Mac.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct MacWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MacSnapshotEntry

    private var primary: WidgetLedgerPresentation {
        WidgetLedgerPresentation(
            snapshot: entry.snapshot,
            ledger: entry.primaryLedger,
            accuracy: .exact
        )
    }

    private var secondary: WidgetLedgerPresentation? {
        guard let ledger = entry.secondaryLedger else { return nil }
        return WidgetLedgerPresentation(
            snapshot: entry.snapshot,
            ledger: ledger,
            accuracy: .exact
        )
    }

    var body: some View {
        switch family {
        case .systemSmall:
            SmallSignalLayout(primary: primary, secondary: secondary)
        case .systemMedium:
            MediumSignalLayout(primary: primary, secondary: secondary)
        case .systemLarge:
            LargeSignalLayout(
                primary: primary,
                secondary: secondary,
                summary: WidgetWeekSummary(
                    snapshot: entry.snapshot,
                    history: entry.history,
                    ledger: entry.primaryLedger,
                    accuracy: .exact
                )
            )
        default:
            SmallSignalLayout(primary: primary, secondary: secondary)
        }
    }
}

// The Mac widget renders the layouts in Shared/WidgetViews.swift. It used to
// carry its own near-identical copies of every view and helper — 500-odd lines
// that had already drifted from the iPhone versions in five places — so the
// duplicates were deleted rather than re-synchronised.
