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
    var height: CGFloat = 8

    var body: some View {
        let color = WidgetStyle.signalColor(presentation)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.16))
                if presentation.fraction > 0 {
                    Capsule()
                        .fill(color)
                        .frame(width: max(height, geo.size.width * presentation.fraction))
                }
            }
        }
        .frame(height: height)
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
                    switch day.status {
                    case .noRecord:
                        // Outline only: nothing was recorded for this day.
                        Capsule()
                            .strokeBorder(NG.line, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    case .noCheckpoint:
                        Capsule().fill(NG.line.opacity(0.5))
                    case .zero:
                        Capsule().fill(NG.line.opacity(0.5))
                        Capsule()
                            .fill(tint.opacity(0.55))
                            .frame(height: 3)
                    case .checkpoint:
                        Capsule().fill(NG.line.opacity(0.5))
                        Capsule()
                            .fill(tint)
                            .frame(height: max(4, geo.size.height * day.fraction))
                    case .reached, .over:
                        Capsule().fill(NG.line.opacity(0.5))
                        Capsule()
                            .fill(NG.alarm)
                            .frame(height: max(6, geo.size.height * max(0.6, day.fraction)))
                    }
                }
            }
            .frame(height: 34)
        }
    }
}

// MARK: - Family layouts
//
// Sized so the tallest realistic content fits the smallest device in each
// family. Every value carries a scale guard, because "≥7h 45m" is far wider
// than the "≥36m" these layouts get mocked up with.

/// Small: the ring is the whole point at this size, with one secondary line.
struct SmallSignalLayout: View {
    let primary: WidgetLedgerPresentation
    let secondary: WidgetLedgerPresentation?

    var body: some View {
        VStack(spacing: 8) {
            WidgetHeader(presentation: primary)
            SignalRing(presentation: primary, size: 78)
            Text(WidgetStyle.status(primary))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(WidgetStyle.statusColor(primary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let secondary {
                SecondaryLedgerRow(presentation: secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Medium: primary ring beside a secondary ring, with the status text under
/// each. Two rings read as one system; a ring plus a bar did not.
struct MediumSignalLayout: View {
    let primary: WidgetLedgerPresentation
    let secondary: WidgetLedgerPresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(presentation: primary)
            HStack(spacing: 16) {
                ledgerColumn(primary, ringSize: 82, emphasised: true)
                if let secondary {
                    Rectangle()
                        .fill(NG.line)
                        .frame(width: 1)
                        .accessibilityHidden(true)
                    ledgerColumn(secondary, ringSize: 74, emphasised: false)
                } else {
                    Rectangle()
                        .fill(NG.line)
                        .frame(width: 1)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Everything else")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(NG.ink)
                        Text("stays untracked.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(NG.inkSoft)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func ledgerColumn(
        _ presentation: WidgetLedgerPresentation,
        ringSize: CGFloat,
        emphasised: Bool
    ) -> some View {
        VStack(spacing: 6) {
            SignalRing(presentation: presentation, size: ringSize)
            Text(presentation.ledger.title.uppercased())
                .font(.ngLabel(emphasised ? 10 : 9.5))
                .tracking(1.5)
                .foregroundStyle(NG.inkSoft)
                .lineLimit(1)
            Text(WidgetStyle.status(presentation))
                .font(.system(size: emphasised ? 11 : 10.5, weight: .semibold))
                .foregroundStyle(WidgetStyle.statusColor(presentation))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Large: both rings plus the seven-day strip. One explanatory line, not three.
struct LargeSignalLayout: View {
    let primary: WidgetLedgerPresentation
    let secondary: WidgetLedgerPresentation?
    let summary: WidgetWeekSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetHeader(presentation: primary)

            HStack(spacing: 18) {
                VStack(spacing: 6) {
                    SignalRing(presentation: primary, size: 104)
                    Text(primary.ledger.title.uppercased())
                        .font(.ngLabel(10))
                        .tracking(1.6)
                        .foregroundStyle(NG.inkSoft)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(WidgetStyle.status(primary))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WidgetStyle.statusColor(primary))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    if let secondary {
                        Divider()
                        SecondaryLedgerRow(presentation: secondary)
                        Text(WidgetStyle.status(secondary))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(NG.inkSoft)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            WeekCrossingStrip(summary: summary, ledger: primary.ledger)

            Text("Only selected apps are counted. Nothing is blocked.")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(NG.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .contain)
    }
}
