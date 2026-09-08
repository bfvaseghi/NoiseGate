import SwiftUI

// MARK: - Shared widget view layer
//
// Both platform widgets render from these. They previously kept two
// near-identical copies of every layout, which had already drifted apart in
// several places, and neither used the design system's signature ring.
// Everything here is driven by `WidgetLedgerPresentation`, so iPhone lower
// bounds and Mac exact values stay honest without the views knowing which is
// which.

// MARK: - Style resolution

enum WidgetStyle {
    static func ledgerColor(_ ledger: WidgetLedger) -> Color {
        ledger == .distractions ? NG.distraction : NG.msg
    }

    /// Colour of the value and the ring sweep.
    static func signalColor(_ presentation: WidgetLedgerPresentation) -> Color {
        switch presentation.level {
        case .notConfigured, .waitingForCheckpoint: return NG.inkSoft
        case .reached, .over: return NG.alarm
        default: return ledgerColor(presentation.ledger)
        }
    }

    static func statusColor(_ presentation: WidgetLedgerPresentation) -> Color {
        switch presentation.level {
        case .reached, .over: return NG.alarm
        case .notConfigured, .waitingForCheckpoint: return NG.inkSoft
        default: return NG.inkSoft
        }
    }

    /// A distinct glyph per level, so state survives tinted and monochrome
    /// home screens, StandBy, and colour-blind viewing — none of which
    /// preserve the orange/teal/red encoding.
    static func symbol(_ presentation: WidgetLedgerPresentation) -> String {
        switch presentation.level {
        case .notConfigured: return "circle.dotted"
        case .waitingForCheckpoint: return "circle"
        case .clear: return "circle.bottomhalf.filled"
        case .watch: return "circle.lefthalf.filled"
        case .high: return "circle.fill"
        case .reached: return "flag.fill"
        case .over: return "exclamationmark.circle.fill"
        }
    }

    /// Short status line under a value.
    static func status(_ presentation: WidgetLedgerPresentation) -> String {
        guard presentation.isConfigured else { return presentation.signalText }
        guard presentation.monitoringIsActive else { return "Tracking paused" }
        return presentation.signalText
    }
}

// MARK: - Ring

/// The primary read: the signature arc with the value inside it. An
/// unconfigured or checkpoint-less ledger draws a dashed, hollow ring so an
/// empty state never looks like a measured zero.
struct SignalRing: View {
    let presentation: WidgetLedgerPresentation
    var size: CGFloat = 96

    private var isIndeterminate: Bool {
        presentation.level == .notConfigured
            || presentation.level == .waitingForCheckpoint
    }

    var body: some View {
        ZStack {
            RingArc(
                fraction: presentation.fraction,
                color: WidgetStyle.signalColor(presentation),
                size: size,
                isIndeterminate: isIndeterminate
            )
            VStack(spacing: 0) {
                Text(presentation.valueText)
                    .font(.ngNumber(size * 0.215))
                    .foregroundStyle(
                        isIndeterminate ? NG.inkSoft : WidgetStyle.signalColor(presentation)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                if presentation.isConfigured {
                    Text("OF \(presentation.budgetMinutes.asHoursMinutes)")
                        .font(.ngLabel(max(9, size * 0.095)))
                        .tracking(0.8)
                        .foregroundStyle(NG.inkSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(size * 0.2)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.ledger.title)
        .accessibilityValue(presentation.accessibilityValue)
    }
}

// MARK: - Building blocks

struct WidgetHeader: View {
    let presentation: WidgetLedgerPresentation
    var showsBrand: Bool = true

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: WidgetStyle.symbol(presentation))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WidgetStyle.signalColor(presentation))
            if showsBrand {
                Text("NOISEGATE")
                    .font(.ngLabel(9.5))
                    .tracking(1.8)
                    .foregroundStyle(NG.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .accessibilityHidden(true)
    }
}

struct SignalProgressBar: View {
    let presentation: WidgetLedgerPresentation
    var height: CGFloat = 10

    var body: some View {
        SignalSegments(fraction: presentation.isFloor
                       ? min(1, Double(presentation.progressPercent) / 100) : presentation.fraction,
                       tint: WidgetStyle.signalColor(presentation), height: height, count: 30)
        .accessibilityHidden(true)
    }
}

/// Compact one-line reading of the non-focused ledger.
struct SecondaryLedgerRow: View {
    let presentation: WidgetLedgerPresentation

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(WidgetStyle.signalColor(presentation))
                .frame(width: 6, height: 6)
            Text(presentation.ledger.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NG.inkSoft)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(presentation.valueAndBudgetText)
                .font(.ngNumber(11))
                .foregroundStyle(WidgetStyle.signalColor(presentation))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.ledger.title)
        .accessibilityValue(presentation.accessibilityValue)
    }
}

/// Seven-day strip. A day with no record reads as an empty outline, a
/// recorded zero as a flat baseline — the two must not look alike.
struct WeekCrossingStrip: View {
    let summary: WidgetWeekSummary
    let ledger: WidgetLedger

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary.summaryText.uppercased())
                .font(.ngLabel(9.5))
                .tracking(1.6)
                .foregroundStyle(NG.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 5) {
                ForEach(summary.days) { day in
                    VStack(spacing: 4) {
                        DayColumn(day: day, tint: WidgetStyle.ledgerColor(ledger))
                        Text(Self.weekdayLabel(day.date))
                            .font(.ngLabel(10))
                            .foregroundStyle(day.isToday ? NG.ink : NG.inkSoft)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last seven days")
        .accessibilityValue(summary.summaryText)
    }

    private static func weekdayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.narrow))
    }

    private struct DayColumn: View {
        let day: WidgetWeekDay
        let tint: Color

        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    let track = RoundedRectangle(cornerRadius: 4, style: .continuous)
                    switch day.status {
                    case .noRecord:
                        // Outline only: nothing was recorded for this day.
                        track.strokeBorder(
                            NG.line,
                            style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                        )
                    case .noCheckpoint:
                        track.fill(NG.line.opacity(0.5))
                    case .zero:
                        track.fill(NG.line.opacity(0.5))
                        track.fill(tint.opacity(0.55)).frame(height: 3)
                    case .checkpoint:
                        track.fill(NG.line.opacity(0.5))
                        track.fill(tint)
                            .frame(height: max(5, geo.size.height * day.fraction))
                    case .reached:
                        track.fill(NG.line.opacity(0.5))
                        track.fill(NG.alarm)
                            .frame(height: max(7, geo.size.height * max(0.6, day.fraction)))
                    }
                }
            }
            .frame(height: 34)
        }
    }
}

// MARK: - Family layouts

struct WidgetLedgerBlock: View {
    let presentation: WidgetLedgerPresentation
    var valueSize: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(presentation.ledger.title)
                .font(.ngMono(11))
                .foregroundStyle(WidgetStyle.ledgerColor(presentation.ledger))
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(presentation.valueText)
                .font(.ngNumber(valueSize)).monospacedDigit()
                .foregroundStyle(WidgetStyle.signalColor(presentation))
                .lineLimit(1).minimumScaleFactor(0.5)
            if presentation.isConfigured {
                Text("Target · \(presentation.budgetMinutes.asHoursMinutes)")
                    .font(.system(size: 10)).foregroundStyle(NG.inkSoft)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            SignalProgressBar(presentation: presentation)
            Text(WidgetStyle.status(presentation))
                .font(.system(size: 10)).foregroundStyle(WidgetStyle.statusColor(presentation))
                .lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.ledger.title)
        .accessibilityValue(presentation.accessibilityValue
            + (presentation.monitoringIsActive ? "" : ", tracking paused"))
    }
}

struct SmallSignalLayout: View {
    let primary: WidgetLedgerPresentation
    let secondary: WidgetLedgerPresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(primary.ledger.title)
                .font(.ngMono(11))
                .foregroundStyle(WidgetStyle.ledgerColor(primary.ledger))
            Text(primary.valueText)
                .font(.ngNumber(30)).monospacedDigit()
                .foregroundStyle(WidgetStyle.signalColor(primary))
                .lineLimit(1).minimumScaleFactor(0.5)
            Text(primary.isConfigured ? "Target · \(primary.budgetMinutes.asHoursMinutes)" : "Choose apps")
                .font(.system(size: 10)).foregroundStyle(NG.inkSoft)
                .lineLimit(1).minimumScaleFactor(0.75)
            SignalProgressBar(presentation: primary)
            Text(WidgetStyle.status(primary))
                .font(.system(size: 10)).foregroundStyle(NG.inkSoft)
                .lineLimit(1).minimumScaleFactor(0.65)
            if let secondary {
                SecondaryLedgerRow(presentation: secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(primary.ledger.title)
        .accessibilityValue(primary.accessibilityValue
            + (primary.monitoringIsActive ? "" : ", tracking paused")
            + (secondary.map { ". \($0.ledger.title): \($0.accessibilityValue)" } ?? ""))
    }
}

struct MediumSignalLayout: View {
    let primary: WidgetLedgerPresentation
    let secondary: WidgetLedgerPresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(presentation: primary)
            HStack(alignment: .top, spacing: 16) {
                WidgetLedgerBlock(presentation: primary, valueSize: 32)
                if let secondary {
                    Rectangle().fill(NG.line).frame(width: 1).accessibilityHidden(true)
                    WidgetLedgerBlock(presentation: secondary, valueSize: 32)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct LargeSignalLayout: View {
    let primary: WidgetLedgerPresentation
    let secondary: WidgetLedgerPresentation?
    let summary: WidgetWeekSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WidgetHeader(presentation: primary)
            WidgetLedgerBlock(presentation: primary, valueSize: 44)
            if let secondary {
                Divider()
                SecondaryLedgerRow(presentation: secondary)
            }
            Spacer(minLength: 0)
            WeekCrossingStrip(summary: summary, ledger: primary.ledger)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
