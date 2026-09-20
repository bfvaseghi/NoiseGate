import AppIntents
import SwiftUI
import UIKit
import WidgetKit

// Tests/WidgetPreview compiles this file into a test bundle with
// WIDGET_PREVIEW defined so it can render the views; a test bundle must not
// carry an entry point.
#if !WIDGET_PREVIEW
@main
#endif
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
        sampleEntry(focus: .automatic, includeHistory: Self.showsHistory(context))
    }

    func snapshot(
        for configuration: NoiseGateWidgetIntent,
        in context: Context
    ) async -> SnapshotEntry {
        if context.isPreview {
            return sampleEntry(
                focus: configuration.focus,
                includeHistory: Self.showsHistory(context)
            )
        }
        return makeEntry(
            focus: configuration.focus,
            includeHistory: Self.showsHistory(context)
        )
    }

    func timeline(
        for configuration: NoiseGateWidgetIntent,
        in context: Context
    ) async -> Timeline<SnapshotEntry> {
        let entry = makeEntry(
            focus: configuration.focus,
            includeHistory: Self.showsHistory(context)
        )
        let refresh = WidgetRefreshSchedule.iOSNextRefresh(now: .now)
        return Timeline(entries: [entry], policy: .after(refresh))
    }

    /// History is one locked JSON read per reload, so only the families that
    /// draw the streak line or the week strip pay for it.
    private static func showsHistory(_ context: Context) -> Bool {
        context.family == .systemMedium || context.family == .systemLarge
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

    /// Six finished days, oldest first, so the gallery shows a streak line
    /// and one confirmed crossing in the strip.
    private static var placeholderHistory: [DayRecord] {
        let calendar = Calendar.current
        let exampleMinutes = [18, 32, 45, 22, 30, 29]
        return exampleMinutes.enumerated().compactMap { index, minutes in
            let daysAgo = exampleMinutes.count - index
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: .now) else {
                return nil
            }
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
            NoiseGateWidgetEntryView(entry: entry)
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

/// The view WidgetKit hosts. It reads the family from the environment and
/// hands it to the layout as a value: `widgetFamily` is read-only, and the
/// preview renderer in Tests/WidgetPreview has to draw every family outside
/// WidgetKit.
struct NoiseGateWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        NoiseGateWidgetView(entry: entry, family: family)
    }
}

struct NoiseGateWidgetView: View {
    let entry: SnapshotEntry
    let family: WidgetFamily
    /// Anchors the seven-day strip, the streak and the clock line. WidgetKit
    /// renders against the clock, as before; the preview passes a fixed date
    /// so its output is repeatable.
    var now: Date = Date()
    /// Named in the large footer. The idiom check lives in this target so
    /// `Shared/` never asks UIKit; the preview overrides it to render the
    /// iPad sentence on an iPhone simulator.
    var device: String = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"

    private var content: WidgetSystemContent {
        WidgetSystemContent(
            snapshot: entry.snapshot,
            history: entry.history,
            primaryLedger: entry.primaryLedger,
            secondaryLedger: entry.secondaryLedger,
            accuracy: .lowerBound,
            device: device,
            now: now
        )
    }

    var body: some View {
        let content = self.content
        switch family {
        case .accessoryCircular:
            AccessoryCircle(presentation: content.primary)
        case .accessoryRectangular:
            AccessoryRectangle(
                primary: content.primary,
                time: WidgetClockLine.time(
                    snapshot: entry.snapshot,
                    ledger: entry.primaryLedger,
                    accuracy: .lowerBound,
                    now: now
                )
            )
        case .accessoryInline:
            if let symbol = WidgetStyle.symbol(content.primary) {
                Label {
                    Text(content.primary.inlineText)
                } icon: {
                    Image(systemName: symbol)
                }
            } else {
                Text(content.primary.inlineText)
            }
        case .systemSmall:
            SmallSignalLayout(content: content)
        case .systemMedium:
            MediumSignalLayout(content: content)
        case .systemLarge:
            LargeSignalLayout(content: content)
        default:
            SmallSignalLayout(content: content)
        }
    }
}

// MARK: - Lock Screen families
//
// The system families live in Shared/WidgetViews.swift so the Mac widget
// renders from exactly the same views. Only the family dispatch and the
// accessory families, which are iPhone-only, stay here. The Lock Screen is
// drawn by the system in vibrant monochrome, so nothing here sets a colour.

/// The system gauge, which handles vibrant, accented and StandBy rendering
/// itself. The value inside is hours-only past an hour so the digits never
/// fall under 11 pt. The label slot under the arc holds a glyph only when
/// the arc cannot say it (paused, reached, over, not set up).
private struct AccessoryCircle: View {
    let presentation: WidgetLedgerPresentation

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Gauge(value: presentation.fraction) {
                if let symbol = WidgetStyle.symbol(presentation) {
                    Image(systemName: symbol)
                }
            } currentValueLabel: {
                Text(presentation.compactValueText)
                    .font(.ngNumber(14))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
            .accessibilityLabel(presentation.ledger.title)
            .accessibilityValue(
                "\(presentation.accessibilityValue). \(WidgetStyle.status(presentation))"
            )
        }
    }
}

/// Eyebrow with the hour, the number with its budget on one baseline, and
/// the status, led by its glyph in the states the number cannot show: the
/// number is the point, so it gets the weight.
private struct AccessoryRectangle: View {
    let primary: WidgetLedgerPresentation
    let time: String?

    private var budgetText: String {
        primary.level == .notConfigured
            ? "Choose apps" : "of \(primary.budgetMinutes.asHoursMinutes)"
    }

    private var statusText: String {
        primary.level == .notConfigured
            ? "No apps selected yet" : WidgetStyle.status(primary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(primary.ledger.title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let time {
                    Text(time)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(primary.valueText)
                    .font(.ngNumber(22))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(budgetText)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .widgetAccentable()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let symbol = WidgetStyle.symbol(primary) {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .bold))
                }
                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.92)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(primary.ledger.title)
        .accessibilityValue("\(primary.accessibilityValue). \(statusText)")
    }
}
