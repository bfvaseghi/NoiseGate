import AppIntents
import SwiftUI
import WidgetKit

@main
struct NoiseGateWidgetBundle: WidgetBundle {
    var body: some Widget {
        NoiseGateWidget()
    }
}

enum NoiseGateWidgetFocus: String, AppEnum {
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

struct NoiseGateWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "NoiseGate focus"
    static var description = IntentDescription(
        "Choose which ledger the widget emphasizes."
    )

    @Parameter(title: "Focus", default: .automatic)
    var focus: NoiseGateWidgetFocus
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
    let history: [DayRecord]
    let focus: NoiseGateWidgetFocus

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

    var destination: NoiseGateRoute {
        let primaryIsConfigured = primaryLedger == .distractions
            ? snapshot.distractionsConfigured : snapshot.messagesConfigured
        return primaryIsConfigured ? .today : .apps
    }
}

struct SnapshotProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        sampleEntry(focus: .automatic, includeHistory: context.family == .systemLarge)
    }

    func snapshot(
        for configuration: NoiseGateWidgetIntent,
        in context: Context
    ) async -> SnapshotEntry {
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
        for configuration: NoiseGateWidgetIntent,
        in context: Context
    ) async -> Timeline<SnapshotEntry> {
        let entry = makeEntry(
            focus: configuration.focus,
            includeHistory: context.family == .systemLarge
        )
        let refresh = WidgetRefreshSchedule.iOSNextRefresh(now: .now)
        return Timeline(entries: [entry], policy: .after(refresh))
    }

    private func makeEntry(
        focus: NoiseGateWidgetFocus,
        includeHistory: Bool
    ) -> SnapshotEntry {
        SnapshotEntry(
            date: .now,
            snapshot: UsageSnapshot.loadToday(),
            history: includeHistory ? HistoryStore.load() : [],
            focus: focus
        )
    }

    private func sampleEntry(
        focus: NoiseGateWidgetFocus,
        includeHistory: Bool
    ) -> SnapshotEntry {
        SnapshotEntry(
            date: .now,
            snapshot: UsageSnapshot(
                distractionMinutes: 36,
                messagesMinutes: 20,
                distractionBudgetMinutes: 45,
                messagesBudgetMinutes: 60,
                distractionsConfigured: true,
                messagesConfigured: true,
                isFloor: true,
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
                isFloor: true
            )
        }
    }
}

struct NoiseGateWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "NoiseGateWidget",
            intent: NoiseGateWidgetIntent.self,
            provider: SnapshotProvider()
        ) { entry in
            NoiseGateWidgetView(entry: entry)
                .containerBackground(NG.paper, for: .widget)
                .widgetURL(entry.destination.url)
        }
        .configurationDisplayName("NoiseGate")
        .description("Distractions first, Messages separate, everything else excluded.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

struct NoiseGateWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var primary: WidgetLedgerPresentation {
        WidgetLedgerPresentation(
            snapshot: entry.snapshot,
            ledger: entry.primaryLedger,
            accuracy: .lowerBound
        )
    }

    private var secondary: WidgetLedgerPresentation? {
        guard let ledger = entry.secondaryLedger else { return nil }
        return WidgetLedgerPresentation(
            snapshot: entry.snapshot,
            ledger: ledger,
            accuracy: .lowerBound
        )
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            AccessoryCircle(presentation: primary)
        case .accessoryRectangular:
            AccessoryRectangle(primary: primary, secondary: secondary)
        case .accessoryInline:
            // Inline accessories get roughly a third of a line, so this is the
            // ledger and the value and nothing else.
            Text("\(primary.ledger.title) \(primary.valueText)")
        case .systemSmall:
            SmallSignalWidget(primary: primary, secondary: secondary)
        case .systemMedium:
            MediumSignalWidget(primary: primary, secondary: secondary)
        case .systemLarge:
            LargeSignalWidget(
                primary: primary,
                secondary: secondary,
                summary: WidgetWeekSummary(
                    snapshot: entry.snapshot,
                    history: entry.history,
                    ledger: entry.primaryLedger,
                    accuracy: .lowerBound
                )
            )
        default:
            SmallSignalWidget(primary: primary, secondary: secondary)
        }
    }
}

private struct AccessoryCircle: View {
    let presentation: WidgetLedgerPresentation

    var body: some View {
        Gauge(value: presentation.fraction) {
            Image(systemName: accessorySymbol(presentation))
        } currentValueLabel: {
            Text(presentation.valueText)
                .minimumScaleFactor(0.55)
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityLabel(presentation.ledger.title)
        .accessibilityValue("\(presentation.accessibilityValue). \(trackingStatus(presentation))")
    }
}

private struct AccessoryRectangle: View {
    let primary: WidgetLedgerPresentation
    let secondary: WidgetLedgerPresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(primary.ledger.title, systemImage: headerSymbol(primary))
                .font(.headline)
            Text(primary.valueAndBudgetText)
                .font(.caption)
            if primary.level == .notConfigured || !primary.monitoringIsActive {
                Text(trackingStatus(primary))
                    .font(.caption2)
            } else if let secondary {
                Text("\(secondary.ledger.title) \(secondary.valueAndBudgetText)")
                    .font(.caption2)
            } else {
                Text(trackingStatus(primary))
                    .font(.caption2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(primary.ledger.title)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let secondaryValue = secondary.map {
            ". \($0.ledger.title), \($0.accessibilityValue)"
        } ?? ""
        return "\(primary.accessibilityValue). \(trackingStatus(primary))\(secondaryValue)"
    }
}

// MARK: - System families
//
// The layouts themselves live in Shared/WidgetViews.swift so the Mac widget
// renders from exactly the same views. Only the family dispatch and the
// accessory families, which are iPhone-only, stay here.

private struct SmallSignalWidget: View {
    let primary: WidgetLedgerPresentation
    let secondary: WidgetLedgerPresentation?

    var body: some View {
        SmallSignalLayout(primary: primary, secondary: secondary)
    }
}

private struct MediumSignalWidget: View {
    let primary: WidgetLedgerPresentation
    let secondary: WidgetLedgerPresentation?

    var body: some View {
        MediumSignalLayout(primary: primary, secondary: secondary)
    }
}

private struct LargeSignalWidget: View {
    let primary: WidgetLedgerPresentation
    let secondary: WidgetLedgerPresentation?
    let summary: WidgetWeekSummary

    var body: some View {
        LargeSignalLayout(primary: primary, secondary: secondary, summary: summary)
    }
}

private func accessorySymbol(_ presentation: WidgetLedgerPresentation) -> String {
    WidgetStyle.symbol(presentation)
}

private func headerSymbol(_ presentation: WidgetLedgerPresentation) -> String {
    WidgetStyle.symbol(presentation)
}

private func trackingStatus(_ presentation: WidgetLedgerPresentation) -> String {
    WidgetStyle.status(presentation)
}
