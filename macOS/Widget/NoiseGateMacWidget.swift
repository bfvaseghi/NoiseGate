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
        let entry = makeEntry(
            focus: configuration.focus,
            includeHistory: context.family == .systemLarge,
            now: now
        )
        let refresh = WidgetRefreshSchedule.macNextRefresh(
            snapshot: entry.snapshot,
            now: now
        )
        return Timeline(entries: [entry], policy: .after(refresh))
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
            MacSmallSignalWidget(primary: primary, secondary: secondary)
        case .systemMedium:
            MacMediumSignalWidget(primary: primary, secondary: secondary)
        case .systemLarge:
            MacLargeSignalWidget(
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
            MacSmallSignalWidget(primary: primary, secondary: secondary)
        }
    }
}

private struct MacSmallSignalWidget: View {
    let primary: WidgetLedgerPresentation
    let secondary: WidgetLedgerPresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            MacWidgetHeader(presentation: primary)
            Text(primary.ledger.title.uppercased())
                .font(.ngLabel(9))
                .tracking(1.5)
                .foregroundStyle(NG.inkSoft)
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(primary.valueText)
                    .font(.ngNumber(27))
                    .foregroundStyle(macValueColor(primary))
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                if primary.isConfigured {
                    Text("OF \(primary.budgetMinutes.asHoursMinutes)")
                        .font(.ngLabel(8))
                        .foregroundStyle(NG.inkSoft)
                }
            }
            MacSignalProgressBar(presentation: primary, height: 7)
            Text(macTrackingStatus(primary))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(macStatusColor(primary))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
            if let secondary {
                HStack(spacing: 5) {
                    Circle()
                        .fill(macSignalColor(secondary))
                        .frame(width: 6, height: 6)
                    Text(secondary.ledger.title)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(NG.inkSoft)
                    Spacer(minLength: 2)
                    Text(secondary.valueAndBudgetText)
                        .font(.ngNumber(9))
                        .foregroundStyle(macValueColor(secondary))
                        .lineLimit(1)
                    if secondary.level == .reached || secondary.level == .over {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(NG.alarm)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(secondary.ledger.title)
                .accessibilityValue(secondary.accessibilityValue)
            } else {
                Text("Everything else is excluded")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(NG.inkSoft)
            }
        }
    }
}

private struct MacMediumSignalWidget: View {
    let primary: WidgetLedgerPresentation
    let secondary: WidgetLedgerPresentation?

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                MacWidgetHeader(presentation: primary)
                Text(primary.ledger.title.uppercased())
                    .font(.ngLabel(10))
                    .tracking(1.6)
                    .foregroundStyle(NG.inkSoft)
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(primary.valueText)
                        .font(.ngNumber(39))
                        .foregroundStyle(macValueColor(primary))
                    if primary.isConfigured {
                        Text("/ \(primary.budgetMinutes.asHoursMinutes)")
                            .font(.ngNumber(13))
                            .foregroundStyle(NG.inkSoft)
                    }
                }
                MacSignalProgressBar(presentation: primary, height: 9)
                Text(macTrackingStatus(primary))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(macStatusColor(primary))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(NG.line)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 10) {
                if let secondary {
                    Text(secondary.ledger.title.uppercased())
                        .font(.ngLabel(9))
                        .tracking(1.5)
                        .foregroundStyle(NG.inkSoft)
                    Text(secondary.valueText)
                        .font(.ngNumber(23))
                        .foregroundStyle(macValueColor(secondary))
                    MacSignalProgressBar(presentation: secondary, height: 6)
                    Text(macTrackingStatus(secondary))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(macStatusColor(secondary))
                        .lineLimit(2)
                } else {
                    Image(systemName: "waveform.slash")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(NG.alarm)
                        .accessibilityHidden(true)
                    Text("Everything else stays excluded.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NG.inkSoft)
                }
            }
            .frame(width: 102, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct MacLargeSignalWidget: View {
    let primary: WidgetLedgerPresentation
    let secondary: WidgetLedgerPresentation?
    let summary: WidgetWeekSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MacWidgetHeader(presentation: primary)

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(primary.ledger.title.uppercased())
                        .font(.ngLabel(10))
                        .tracking(1.7)
                        .foregroundStyle(NG.inkSoft)
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(primary.valueText)
                            .font(.ngNumber(45))
                            .foregroundStyle(macValueColor(primary))
                        if primary.isConfigured {
                            Text("OF \(primary.budgetMinutes.asHoursMinutes)")
                                .font(.ngLabel(10))
                                .foregroundStyle(NG.inkSoft)
                        }
                    }
                    MacSignalProgressBar(presentation: primary, height: 10)
                    Text(macTrackingStatus(primary))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(macStatusColor(primary))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let secondary {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(secondary.ledger.title.uppercased())
                            .font(.ngLabel(9))
                            .tracking(1.5)
                            .foregroundStyle(NG.inkSoft)
                        Text(secondary.valueText)
                            .font(.ngNumber(25))
                            .foregroundStyle(macValueColor(secondary))
                        Text(secondary.isConfigured
                            ? "OF \(secondary.budgetMinutes.asHoursMinutes)"
                            : "NOT SET")
                            .font(.ngLabel(8))
                            .foregroundStyle(NG.inkSoft)
                        MacSignalProgressBar(presentation: secondary, height: 6)
                        Text(macTrackingStatus(secondary))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(macStatusColor(secondary))
                            .lineLimit(1)
                    }
                    .frame(width: 105, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }

            Rectangle()
                .fill(NG.line)
                .frame(height: 1)

            MacWeekView(summary: summary)

            HStack {
                Text(summary.summaryText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NG.inkSoft)
                Spacer()
                Text("Everything else is excluded")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NG.inkSoft)
            }
        }
    }
}

private struct MacWeekView: View {
    let summary: WidgetWeekSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SEVEN DAYS · \(summary.ledger.title.uppercased())")
                .font(.ngLabel(9))
                .tracking(1.5)
                .foregroundStyle(NG.inkSoft)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(summary.days) { day in
                    VStack(spacing: 5) {
                        GeometryReader { geometry in
                            ZStack(alignment: .bottom) {
                                Capsule().fill(NG.line.opacity(0.65))
                                if day.status == .noRecord {
                                    Capsule()
                                        .strokeBorder(NG.inkSoft.opacity(0.45), lineWidth: 1)
                                } else {
                                    Capsule()
                                        .fill(day.status == .reached
                                            ? NG.alarm : macLedgerColor(summary.ledger))
                                        .frame(height: max(
                                            day.minutes > 0 ? 4 : 2,
                                            geometry.size.height * day.fraction
                                        ))
                                }
                            }
                        }
                        .frame(height: 45)
                        Text(day.date, format: .dateTime.weekday(.narrow))
                            .font(.system(size: 9, weight: day.isToday ? .bold : .medium))
                            .foregroundStyle(day.isToday ? NG.ink : NG.inkSoft)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
                    .accessibilityValue(macDayAccessibilityValue(day))
                }
            }
        }
    }
}

private struct MacWidgetHeader: View {
    let presentation: WidgetLedgerPresentation

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.slash")
                .foregroundStyle(NG.alarm)
                .accessibilityHidden(true)
            Text("NOISEGATE")
                .font(.ngLabel(9.5))
                .tracking(1.8)
                .foregroundStyle(NG.ink)
            Spacer()
            Image(systemName: macHeaderSymbol(presentation))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(macHeaderColor(presentation))
                .accessibilityHidden(true)
        }
    }
}

private struct MacSignalProgressBar: View {
    let presentation: WidgetLedgerPresentation
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(macLedgerColor(presentation.ledger).opacity(0.14))
                Capsule()
                    .fill(macSignalColor(presentation))
                    .frame(width: geometry.size.width * presentation.fraction)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

private func macLedgerColor(_ ledger: WidgetLedger) -> Color {
    ledger == .distractions ? NG.distraction : NG.msg
}

private func macSignalColor(_ presentation: WidgetLedgerPresentation) -> Color {
    presentation.level == .reached || presentation.level == .over
        ? NG.alarm : macLedgerColor(presentation.ledger)
}

private func macValueColor(_ presentation: WidgetLedgerPresentation) -> Color {
    presentation.level == .reached || presentation.level == .over
        ? NG.alarm : NG.ink
}

private func macStatusColor(_ presentation: WidgetLedgerPresentation) -> Color {
    presentation.monitoringIsActive ? NG.ink : NG.inkSoft
}

private func macHeaderColor(_ presentation: WidgetLedgerPresentation) -> Color {
    guard presentation.monitoringIsActive else { return NG.inkSoft }
    return presentation.level == .reached || presentation.level == .over
        ? NG.alarm : NG.inkSoft
}

private func macHeaderSymbol(_ presentation: WidgetLedgerPresentation) -> String {
    if presentation.level == .notConfigured { return "plus.circle" }
    guard presentation.monitoringIsActive else { return "pause.circle.fill" }
    switch presentation.level {
    case .notConfigured: return "plus.circle"
    case .waitingForCheckpoint: return "circle.dotted"
    case .clear: return "circle"
    case .watch: return "circle.bottomhalf.filled"
    case .high: return "circle.fill"
    case .reached: return "flag.fill"
    case .over: return "exclamationmark.circle.fill"
    }
}

private func macTrackingStatus(_ presentation: WidgetLedgerPresentation) -> String {
    guard presentation.level != .notConfigured else {
        return presentation.signalText
    }
    guard presentation.monitoringIsActive else {
        return "Last tally · Tracking paused"
    }
    switch presentation.level {
    case .clear, .watch, .high:
        return "\((presentation.budgetMinutes - presentation.minutes).asHoursMinutes) remaining"
    default:
        return presentation.signalText
    }
}

private func macDayAccessibilityValue(_ day: WidgetWeekDay) -> String {
    switch day.status {
    case .noRecord: return "No record"
    case .noCheckpoint, .zero: return "Zero minutes"
    case .checkpoint: return "\(day.minutes) minutes"
    case .reached: return "\(day.minutes) minutes. Budget crossed"
    }
}
