import SwiftUI
import WidgetKit

// MARK: - Shared widget view layer
//
// Both platform widgets render from these. Everything here is driven by
// `WidgetLedgerPresentation`, so iPhone lower bounds and Mac exact values stay
// honest without the views knowing which is which. The widget is one
// instrument at every size: a thick solid ring with the number inside it on
// the app's paper, and beside it the three facts worth a glance — how far
// into today's budget, how many finished days without a crossing, and when
// the number was last raised. Nothing renders under 11 pt.

// MARK: - Style resolution

enum WidgetStyle {
    static func ledgerColor(_ ledger: WidgetLedger) -> Color {
        ledger == .distractions ? NG.distraction : NG.msg
    }

    /// Colour of the ring sweep, its dot and the state glyph. A paused
    /// ledger keeps its level colour: the floor is still true.
    static func signalColor(_ presentation: WidgetLedgerPresentation) -> Color {
        switch presentation.level {
        case .notConfigured, .waitingForCheckpoint: return NG.inkSoft
        case .reached, .over: return NG.alarm
        default: return ledgerColor(presentation.ledger)
        }
    }

    /// The numeral is ink, not the ledger colour: amber on paper is 2.9:1.
    static func numeralColor(_ presentation: WidgetLedgerPresentation) -> Color {
        switch presentation.level {
        case .notConfigured, .waitingForCheckpoint: return NG.inkSoft
        case .reached, .over: return NG.alarm
        default: return NG.ink
        }
    }

    /// Colour of the medium and large status line.
    static func statusColor(_ presentation: WidgetLedgerPresentation) -> Color {
        guard presentation.isConfigured, presentation.monitoringIsActive else {
            return NG.inkSoft
        }
        switch presentation.level {
        case .reached, .over: return NG.alarm
        case .notConfigured, .waitingForCheckpoint: return NG.inkSoft
        default: return NG.ink
        }
    }

    /// Colour of the small family's compact status line.
    static func compactStatusColor(_ presentation: WidgetLedgerPresentation) -> Color {
        guard presentation.isConfigured, presentation.monitoringIsActive else {
            return NG.inkSoft
        }
        switch presentation.level {
        case .reached, .over: return NG.alarm
        default: return NG.inkSoft
        }
    }

    /// A distinct glyph per state, so state survives tinted and monochrome
    /// home screens, StandBy, and colour-blind viewing — none of which
    /// preserve the orange/teal/red encoding. A stopped monitor comes first:
    /// the level is still a fact, but it is no longer moving.
    static func symbol(_ presentation: WidgetLedgerPresentation) -> String {
        if presentation.isConfigured && !presentation.monitoringIsActive {
            return "pause.circle"
        }
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

// MARK: - Content

/// Everything the system families draw, derived once per entry by the
/// platform widget from its snapshot and history. Pure: the store is read in
/// the timeline provider, never here.
struct WidgetSystemContent {
    let primary: WidgetLedgerPresentation
    let secondary: WidgetLedgerPresentation?
    let streak: WidgetStreakLine
    let clock: String?
    let masthead: String?
    let summary: WidgetWeekSummary
    /// "iPhone", "iPad" or "Mac", named in the large footer. The platform
    /// target decides it so `Shared/` never asks UIKit.
    let device: String

    init(
        snapshot: UsageSnapshot,
        history: [DayRecord],
        primaryLedger: WidgetLedger,
        secondaryLedger: WidgetLedger?,
        accuracy: WidgetAccuracy,
        device: String,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) {
        primary = WidgetLedgerPresentation(
            snapshot: snapshot,
            ledger: primaryLedger,
            accuracy: accuracy
        )
        secondary = secondaryLedger.map {
            WidgetLedgerPresentation(snapshot: snapshot, ledger: $0, accuracy: accuracy)
        }
        streak = WidgetStreakLine(
            snapshot: snapshot,
            history: history,
            ledger: primaryLedger,
            accuracy: accuracy,
            now: now,
            calendar: calendar
        )
        clock = WidgetClockLine.text(
            snapshot: snapshot,
            ledger: primaryLedger,
            accuracy: accuracy,
            now: now,
            calendar: calendar
        )
        masthead = WidgetClockLine.masthead(
            snapshot: snapshot,
            ledger: primaryLedger,
            accuracy: accuracy,
            now: now,
            calendar: calendar
        )
        summary = WidgetWeekSummary(
            snapshot: snapshot,
            history: history,
            ledger: primaryLedger,
            accuracy: accuracy,
            now: now,
            calendar: calendar
        )
        self.device = device
    }
}

// MARK: - Ring

/// The primary read: the signature arc with the value inside it. An
/// unconfigured or checkpoint-less ledger draws a dashed, hollow ring so an
/// empty state never looks like a measured zero.
struct SignalRing: View {
    let presentation: WidgetLedgerPresentation
    /// The ring's visible diameter, which is also its layout frame.
    var size: CGFloat = 96
    var numeralSize: CGFloat = 22
    var showsBudgetInside: Bool = true

    /// `RingArc` strokes the circle inscribed in its frame, so half its
    /// stroke paints outside that frame. The arc is drawn smaller so the
    /// paint ends at `size` and the ring sits on the same margin as the text
    /// beside it instead of spilling past it. Mirrors the arc's own stroke
    /// rule, `max(6, arcSize × 0.105)`.
    private var arcSize: CGFloat { min(size / 1.105, size - 6) }
    private var stroke: CGFloat { max(6, arcSize * 0.105) }
    /// From the frame edge to the ring's inner edge, plus 3 pt of air.
    private var textInset: CGFloat { (size - arcSize + stroke) / 2 + 3 }

    private var isIndeterminate: Bool {
        presentation.level == .notConfigured
            || presentation.level == .waitingForCheckpoint
    }

    var body: some View {
        ZStack {
            RingArc(
                fraction: presentation.fraction,
                color: WidgetStyle.signalColor(presentation),
                size: arcSize,
                isIndeterminate: isIndeterminate,
                sweep: .solid
            )
            .widgetAccentable()
            VStack(spacing: 0) {
                Text(presentation.valueText)
                    .font(.ngNumber(numeralSize))
                    .foregroundStyle(WidgetStyle.numeralColor(presentation))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if showsBudgetInside && presentation.isConfigured {
                    Text("OF \(presentation.budgetMinutes.asHoursMinutes)")
                        .font(.ngLabel(11))
                        .tracking(0.8)
                        .foregroundStyle(NG.inkSoft)
                        .lineLimit(1)
                }
            }
            .padding(textInset)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.ledger.title)
        .accessibilityValue(presentation.accessibilityValue)
    }
}

// MARK: - Building blocks

/// Ledger name in small caps with the state glyph beside it, so the glyph
/// reads as the label's own indicator rather than a dot adrift at the far
/// edge of the column. The name never truncates: on a canvas too narrow for
/// both, the glyph is dropped and the words still carry the state.
struct LedgerEyebrow: View {
    let presentation: WidgetLedgerPresentation
    /// 1.5 in the medium and large columns; the small canvas is 126 pt wide,
    /// where "DISTRACTIONS" at 1.5 plus the glyph is a hair too wide.
    var tracking: CGFloat = 1.5

    private var title: some View {
        Text(presentation.ledger.title.uppercased())
            .font(.ngLabel(11))
            .tracking(tracking)
            .foregroundStyle(NG.inkSoft)
            .lineLimit(1)
            .accessibilityLabel(presentation.ledger.title)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                title
                Image(systemName: WidgetStyle.symbol(presentation))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WidgetStyle.signalColor(presentation))
                    .widgetAccentable()
                    .accessibilityHidden(true)
            }
            title
        }
    }
}

/// 12 pt running text in ink-soft; the scale floor keeps it at or above 11 pt.
struct DetailLine: ViewModifier {
    var lines = 1

    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(NG.inkSoft)
            .lineLimit(lines)
            .minimumScaleFactor(0.92)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(NG.line)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// Compact one-line reading of the non-focused ledger. The reading is tried
/// at 12 pt, then at the 11 pt floor, then without its budget, so a number
/// is never cut with an ellipsis: "≥1h 05m / 1h 00m" beside "Messages" only
/// fits the 186 pt column at 11 pt, and beside "Distractions" not at all.
struct SecondaryLedgerRow: View {
    let presentation: WidgetLedgerPresentation

    private var hasNumber: Bool {
        presentation.level != .notConfigured
            && presentation.level != .waitingForCheckpoint
    }

    /// The last resort: the value alone, or the app's dash for a ledger with
    /// no checkpoint yet. "Not set" is short enough to keep.
    private var compactReading: String {
        presentation.level == .notConfigured
            ? presentation.valueAndBudgetText : presentation.valueText
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(presentation.valueAndBudgetText, size: 12)
            row(presentation.valueAndBudgetText, size: 11)
            row(compactReading, size: 12)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.ledger.title)
        .accessibilityValue(presentation.accessibilityValue)
    }

    /// Numerals in the number face; words ("Not set", "No checkpoint yet")
    /// in the running-text face, which is narrower and is what they are.
    private func readingFont(_ size: CGFloat) -> Font {
        hasNumber ? Font.ngNumber(size) : Font.system(size: size, weight: .semibold)
    }

    private func row(_ reading: String, size: CGFloat) -> some View {
        HStack(spacing: 0) {
            Circle()
                .fill(WidgetStyle.signalColor(presentation))
                .frame(width: 6, height: 6)
                .widgetAccentable()
            Text(presentation.ledger.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NG.inkSoft)
                .lineLimit(1)
                .padding(.leading, 6)
            Text(reading)
                .font(readingFont(size))
                .foregroundStyle(WidgetStyle.signalColor(presentation))
                .lineLimit(1)
                .padding(.leading, 6)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// Seven-day strip. A day with no record reads as an empty outline, a
/// recorded zero as a flat baseline — the two must not look alike.
struct WeekCrossingStrip: View {
    let summary: WidgetWeekSummary
    let ledger: WidgetLedger

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LAST 7 DAYS · \(summary.summaryText.uppercased())")
                .font(.ngLabel(11))
                .tracking(1.5)
                .foregroundStyle(NG.inkSoft)
                .lineLimit(1)
            HStack(spacing: 6) {
                ForEach(summary.days) { day in
                    VStack(spacing: 4) {
                        DayColumn(day: day, tint: WidgetStyle.ledgerColor(ledger))
                        Text(Self.weekdayLabel(day.date))
                            .font(.ngLabel(11))
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
            .frame(height: Self.height)
        }

        /// Tall enough that the strip, not a blank band, holds the middle
        /// of the 322 pt large canvas.
        static let height: CGFloat = 64
    }
}

// MARK: - Family layouts
//
// Sized for the iPhone 15/16 Pro canvases (126×126, 306×126 and 306×322
// inside the system margins). Every scale factor is chosen so size × factor
// stays at or above 11 pt against the widest strings: "≥1h 05m", "OF 8h 00m",
// "At least 1h 05m over budget", "12 days without a crossing".

/// Small: the number. Eyebrow, ring with the value alone inside it, and one
/// compact status line that names the budget the ring has no room for; all
/// three centred, one dial with its label above and its reading below.
struct SmallSignalLayout: View {
    let primary: WidgetLedgerPresentation

    var body: some View {
        VStack(spacing: 5) {
            LedgerEyebrow(presentation: primary, tracking: 1)
            SignalRing(
                presentation: primary,
                size: 84,
                numeralSize: 19,
                showsBudgetInside: false
            )
            Text(primary.compactSignalText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WidgetStyle.compactStatusColor(primary))
                .lineLimit(1)
                .minimumScaleFactor(0.92)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Medium: the ring is the instrument, the column beside it is the ledger.
/// Sized for a 306×126 canvas; the column never exceeds 102 pt tall.
struct MediumSignalLayout: View {
    let primary: WidgetLedgerPresentation
    let secondary: WidgetLedgerPresentation?
    let streak: WidgetStreakLine
    let clock: String?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            SignalRing(
                presentation: primary,
                size: 100,
                numeralSize: 22,
                showsBudgetInside: true
            )

            VStack(alignment: .leading, spacing: 4) {
                // One VoiceOver stop for the ledger's own lines; the secondary
                // row below keeps its own label and value.
                VStack(alignment: .leading, spacing: 4) {
                    LedgerEyebrow(presentation: primary)
                    Text(WidgetStyle.status(primary))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WidgetStyle.statusColor(primary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let line = streak.text {
                        Text(line).modifier(DetailLine())
                    }
                    if let clock {
                        Text(clock).modifier(DetailLine())
                    }
                }
                .accessibilityElement(children: .combine)
                if let secondary {
                    Hairline()
                        .padding(.vertical, 3)
                    SecondaryLedgerRow(presentation: secondary)
                } else {
                    Text("Only selected apps are counted. Nothing is blocked.")
                        .modifier(DetailLine(lines: 2))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Large: masthead, the hero ring with a status that may take two lines, the
/// seven-day strip, and one sentence naming the device the numbers come
/// from. Three fixed blocks; the two spacers share what is left of the 322 pt
/// so the strip never floats in a blank band.
struct LargeSignalLayout: View {
    let primary: WidgetLedgerPresentation
    let secondary: WidgetLedgerPresentation?
    let streak: WidgetStreakLine
    let masthead: String?
    let summary: WidgetWeekSummary
    let device: String

    private var footer: String {
        "Only selected apps on this \(device) are counted. Nothing is blocked."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // The app's own typographic mark: the brand word with a red
                // full stop, the only brand red in any family.
                (Text("NOISEGATE").foregroundStyle(NG.ink)
                    + Text(".").foregroundStyle(NG.alarm))
                    .font(.ngLabel(11))
                    .tracking(2)
                    .lineLimit(1)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                if let masthead {
                    Text(masthead)
                        .font(.ngLabel(11))
                        .tracking(1.5)
                        .foregroundStyle(NG.inkSoft)
                        .lineLimit(1)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                SignalRing(
                    presentation: primary,
                    size: 104,
                    numeralSize: 24,
                    showsBudgetInside: true
                )
                VStack(alignment: .leading, spacing: 4) {
                    VStack(alignment: .leading, spacing: 4) {
                        LedgerEyebrow(presentation: primary)
                        // 16 pt: "At least 80% of budget" fits the 186 pt
                        // column on one line, where 17 pt did not and was
                        // shrunk to its floor. Longer readings wrap.
                        Text(WidgetStyle.status(primary))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(WidgetStyle.statusColor(primary))
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                        if let line = streak.text {
                            Text(line).modifier(DetailLine())
                        }
                    }
                    .accessibilityElement(children: .combine)
                    if let secondary {
                        Hairline()
                            .padding(.vertical, 3)
                        SecondaryLedgerRow(presentation: secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // The outer stack shares its height out among its rows before the
            // spacers claim the rest; without this the column is measured
            // short and its status scales down instead of wrapping.
            .fixedSize(horizontal: false, vertical: true)

            Hairline()
            Spacer(minLength: 0)

            WeekCrossingStrip(summary: summary, ledger: primary.ledger)

            Spacer(minLength: 0)
            Text(footer).modifier(DetailLine(lines: 2))
        }
        .accessibilityElement(children: .contain)
    }
}

extension SmallSignalLayout {
    init(content: WidgetSystemContent) {
        self.init(primary: content.primary)
    }
}

extension MediumSignalLayout {
    init(content: WidgetSystemContent) {
        self.init(
            primary: content.primary,
            secondary: content.secondary,
            streak: content.streak,
            clock: content.clock
        )
    }
}

extension LargeSignalLayout {
    init(content: WidgetSystemContent) {
        self.init(
            primary: content.primary,
            secondary: content.secondary,
            streak: content.streak,
            masthead: content.masthead,
            summary: content.summary,
            device: content.device
        )
    }
}
