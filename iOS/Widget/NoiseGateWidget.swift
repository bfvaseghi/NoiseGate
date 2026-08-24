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
            Text("\(primary.ledger.title) \(primary.valueText) · \(trackingStatus(primary))")
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

private struct SmallSignalWidget: View {
    let primary: WidgetLedgerPresentation
    let secondary: WidgetLedgerPresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            WidgetHeader(presentation: primary)

            Text(primary.ledger.title.uppercased())
                .font(.ngLabel(9))
                .tracking(1.5)
                .foregroundStyle(NG.inkSoft)

            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(primary.valueText)
                    .font(.ngNumber(27))
                    .foregroundStyle(valueColor(primary))
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                if primary.isConfigured {
                    Text("OF \(primary.budgetMinutes.asHoursMinutes)")
                        .font(.ngLabel(8))
                        .tracking(0.7)
                        .foregroundStyle(NG.inkSoft)
                }
            }

            SignalProgressBar(presentation: primary, height: 7)

            Text(trackingStatus(primary))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(statusColor(primary))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 0)

            if let secondary {
                HStack(spacing: 5) {
                    Circle()
                        .fill(signalColor(secondary))
                        .frame(width: 6, height: 6)
                    Text(secondary.ledger.title)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(NG.inkSoft)
                    Spacer(minLength: 2)
                    Text(secondary.valueAndBudgetText)
                        .font(.ngNumber(9))
                        .foregroundStyle(valueColor(secondary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
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
        .accessibilityElement(children: .contain)
    }
}

private struct MediumSignalWidget: View {
    let primary: WidgetLedgerPresentation
    let secondary: WidgetLedgerPresentation?

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(presentation: primary)
                Text(primary.ledger.title.uppercased())
                    .font(.ngLabel(10))
                    .tracking(1.6)
                    .foregroundStyle(NG.inkSoft)
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(primary.valueText)
                        .font(.ngNumber(39))
                        .foregroundStyle(valueColor(primary))
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                    if primary.isConfigured {
                        Text("/ \(primary.budgetMinutes.asHoursMinutes)")
                            .font(.ngNumber(13))
                            .foregroundStyle(NG.inkSoft)
                    }
                }
                SignalProgressBar(presentation: primary, height: 9)
                Text(trackingStatus(primary))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(statusColor(primary))
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
                        .foregroundStyle(valueColor(secondary))
                    SignalProgressBar(presentation: secondary, height: 6)
                    Text(trackingStatus(secondary))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(statusColor(secondary))
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

private struct LargeSignalWidget: View {
    let primary: WidgetLedgerPresentation
    let secondary: WidgetLedgerPresentation?
    let summary: WidgetWeekSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WidgetHeader(presentation: primary)

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(primary.ledger.title.uppercased())
                        .font(.ngLabel(10))
                        .tracking(1.7)
                        .foregroundStyle(NG.inkSoft)
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(primary.valueText)
                            .font(.ngNumber(45))
                            .foregroundStyle(valueColor(primary))
                        if primary.isConfigured {
                            Text("OF \(primary.budgetMinutes.asHoursMinutes)")
                                .font(.ngLabel(10))
                                .tracking(0.8)
                                .foregroundStyle(NG.inkSoft)
                        }
                    }
                    SignalProgressBar(presentation: primary, height: 10)
                    Text(trackingStatus(primary))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(statusColor(primary))
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
                            .foregroundStyle(valueColor(secondary))
                        Text(secondary.isConfigured
                            ? "OF \(secondary.budgetMinutes.asHoursMinutes)"
                            : "NOT SET")
                            .font(.ngLabel(8))
                            .foregroundStyle(NG.inkSoft)
                        SignalProgressBar(presentation: secondary, height: 6)
                        Text(trackingStatus(secondary))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(statusColor(secondary))
                            .lineLimit(1)
                    }
                    .frame(width: 105, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }

            Rectangle()
                .fill(NG.line)
                .frame(height: 1)

            WeekCrossingView(summary: summary)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.summaryText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NG.inkSoft)
                Text("Bars show at least the recorded checkpoint")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NG.inkSoft)
                Text("Everything else is excluded")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NG.inkSoft)
            }
        }
    }
}

private struct WeekCrossingView: View {
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
                                Capsule()
                                    .fill(NG.line.opacity(0.65))
                                if day.status == .noRecord {
                                    Capsule()
                                        .strokeBorder(NG.inkSoft.opacity(0.45), lineWidth: 1)
                                } else {
                                    Capsule()
                                        .fill(day.status == .reached
                                            ? NG.alarm : ledgerColor(summary.ledger))
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
                    .accessibilityValue(accessibilityValue(for: day))
                }
            }
        }
    }

    private func accessibilityValue(for day: WidgetWeekDay) -> String {
        switch day.status {
        case .noRecord: return "No record"
        case .noCheckpoint: return "No checkpoint recorded"
        case .zero: return "Zero minutes"
        case .checkpoint:
            return "At least \(day.minutes) minutes. No crossing confirmed"
        case .reached:
            return "Confirmed budget crossing at \(day.minutes) minutes or more"
        }
    }
}

private struct WidgetHeader: View {
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
            Image(systemName: headerSymbol(presentation))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(headerColor(presentation))
                .accessibilityHidden(true)
        }
    }
}

private struct SignalProgressBar: View {
    let presentation: WidgetLedgerPresentation
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ledgerColor(presentation.ledger).opacity(0.14))
                Capsule()
                    .fill(signalColor(presentation))
                    .frame(width: geometry.size.width * presentation.fraction)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

private func ledgerColor(_ ledger: WidgetLedger) -> Color {
    ledger == .distractions ? NG.distraction : NG.msg
}

private func signalColor(_ presentation: WidgetLedgerPresentation) -> Color {
    presentation.level == .reached || presentation.level == .over
        ? NG.alarm : ledgerColor(presentation.ledger)
}

private func valueColor(_ presentation: WidgetLedgerPresentation) -> Color {
    presentation.level == .reached || presentation.level == .over
        ? NG.alarm : NG.ink
}

private func statusColor(_ presentation: WidgetLedgerPresentation) -> Color {
    presentation.monitoringIsActive ? NG.ink : NG.inkSoft
}

private func headerColor(_ presentation: WidgetLedgerPresentation) -> Color {
    guard presentation.monitoringIsActive else { return NG.inkSoft }
    return presentation.level == .reached || presentation.level == .over
        ? NG.alarm : NG.inkSoft
}

private func headerSymbol(_ presentation: WidgetLedgerPresentation) -> String {
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

private func accessorySymbol(_ presentation: WidgetLedgerPresentation) -> String {
    if presentation.level == .notConfigured { return "plus" }
    guard presentation.monitoringIsActive else { return "pause.fill" }
    return presentation.ledger == .distractions ? "waveform.slash" : "message.fill"
}

private func trackingStatus(_ presentation: WidgetLedgerPresentation) -> String {
    guard presentation.level != .notConfigured else {
        return presentation.signalText
    }
    guard presentation.monitoringIsActive else {
        return "Last checkpoint · Open to resume"
    }
    return presentation.signalText
}
