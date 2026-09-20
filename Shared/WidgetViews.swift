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

    /// The numeral is ink, never the ledger colour (amber on paper is 2.9:1)
    /// and not red either: the ring and the status carry a reached budget,
    /// as the in-app gauge does, so the one meaning red has is not spent
    /// four times on one canvas. Only an empty reading goes soft.
    static func numeralColor(_ presentation: WidgetLedgerPresentation) -> Color {
        switch presentation.level {
        case .notConfigured, .waitingForCheckpoint: return NG.inkSoft
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

    /// A glyph only for the states the ring cannot show on its own, so the
    /// state survives tinted and monochrome home screens, StandBy and
    /// colour-blind viewing without a decoration beside every label. A
    /// stopped monitor comes first: the level is still a fact, but it is no
    /// longer moving. A reached budget is a full ring, which at 150 % looks
    /// the same as at 100 %; the flag and the exclamation tell them apart.
    /// An unconfigured ledger is dotted, so the Lock Screen circle, which
    /// has no words, can still say "not set up" rather than "nothing yet".
    /// Every other level is the sweep itself, and needs no second mark.
    static func symbol(_ presentation: WidgetLedgerPresentation) -> String? {
        if presentation.isConfigured && !presentation.monitoringIsActive {
            return "pause.circle"
        }
        switch presentation.level {
        case .notConfigured: return "circle.dotted"
        case .reached: return "flag.fill"
        case .over: return "exclamationmark.circle.fill"
        case .waitingForCheckpoint, .clear, .watch, .high: return nil
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
    /// The write time alone, for the trailing edge of the eyebrow row.
    /// iPhone only: on the Mac a heartbeat time says nothing.
    let stamp: String?
    /// The running-text line about the tracker. Mac only: "Tracking on this
    /// Mac" or when it last was.
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
        stamp = WidgetClockLine.stamp(
            snapshot: snapshot,
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

/// Ledger name in small caps. In the medium column the write time sits at
/// the row's trailing edge as a stamp — the quietest honest form of
/// "as of" — at label size but in running weight, so the name stays the
/// louder of the two. The name never truncates.
struct LedgerEyebrow: View {
    let presentation: WidgetLedgerPresentation
    var stamp: String? = nil
    /// 1.5 in the medium and large columns; the small canvas is 126 pt wide,
    /// where "DISTRACTIONS" at 1.5 is a hair too wide.
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
        if let stamp {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                title
                Spacer(minLength: 0)
                Text(stamp)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NG.inkSoft)
                    .lineLimit(1)
                    .accessibilityLabel("Updated \(stamp)")
            }
        } else {
            title
        }
    }
}

/// The state in words, led by its glyph in the states where the ring alone
/// could mislead (`WidgetStyle.symbol`). The glyph sits on the first
/// baseline, so a two-line reading wraps under its own words; VoiceOver
/// hears the words only.
struct StatusLine: View {
    let presentation: WidgetLedgerPresentation
    let text: String
    let size: CGFloat
    let weight: Font.Weight
    let color: Color
    var lines: Int = 1
    var minimumScale: CGFloat = 0.8

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let symbol = WidgetStyle.symbol(presentation) {
                Image(systemName: symbol)
                    .font(.system(size: size - 2, weight: .bold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.system(size: size, weight: weight))
                .lineLimit(lines)
                .minimumScaleFactor(minimumScale)
        }
        .foregroundStyle(color)
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
/// recorded zero as a flat baseline — the two must not look alike. A
/// confirmed crossing is red and carries a paper dot at its top: the ring's
/// endpoint dot, set where the sweep met the budget, so the day is marked
/// for a reader who cannot tell red from amber.
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
            HStack(spacing: 8) {
                ForEach(summary.days) { day in
                    VStack(spacing: 4) {
                        DayColumn(day: day, tint: WidgetStyle.ledgerColor(ledger))
                            .frame(maxWidth: DayColumn.width)
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
                            .overlay(alignment: .top) {
                                Circle()
                                    .fill(NG.paper)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 5)
                            }
                    }
                }
            }
            .frame(height: Self.height)
        }

        /// A bar, not a block: narrower than its column so the strip reads
        /// as a chart under the hero ring rather than a wall of colour that
        /// outweighs it, and short enough that the large canvas keeps an
        /// even rhythm around it.
        static let width: CGFloat = 30
        static let height: CGFloat = 48
    }
}

// MARK: - Family layouts
//
// Sized for the iPhone 15/16 Pro canvases (126×126, 306×126 and 306×322
// inside the system margins). Every scale factor is chosen so size × factor
// stays at or above 11 pt against the widest strings: "≥1h 05m", "OF 8h 00m",
// "At least 1h 05m over budget", "12 days without a crossing".

/// Small: the number. A dial with its label above and its reading below,
/// all three centred; the ring holds the value alone and the compact status
/// names the budget the ring has no room for.
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
            StatusLine(
                presentation: primary,
                text: primary.compactSignalText,
                size: 12,
                weight: .semibold,
                color: WidgetStyle.compactStatusColor(primary),
                minimumScale: 0.92
            )
        }
        .accessibilityElement(children: .contain)
    }
}

/// Medium: the ring is the instrument, the column beside it is the ledger.
/// Sized for a 306×126 canvas; the column sits at 92 pt beside the 100 pt
/// ring, or 112 pt on the Mac, whose tracker line is a sentence.
struct MediumSignalLayout: View {
    let primary: WidgetLedgerPresentation
    let secondary: WidgetLedgerPresentation?
    let streak: WidgetStreakLine
    let stamp: String?
    let clock: String?

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            SignalRing(
                presentation: primary,
                size: 100,
                numeralSize: 22,
                showsBudgetInside: true
            )

            VStack(alignment: .leading, spacing: 6) {
                // One VoiceOver stop for the ledger's own lines; the secondary
                // row below keeps its own label and value.
                VStack(alignment: .leading, spacing: 6) {
                    LedgerEyebrow(presentation: primary, stamp: stamp)
                    StatusLine(
                        presentation: primary,
                        text: WidgetStyle.status(primary),
                        size: 15,
                        weight: .bold,
                        color: WidgetStyle.statusColor(primary),
                        minimumScale: 0.8
                    )
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
                        .padding(.vertical, 4)
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
/// from. The masthead hugs the hero; the three spacers share what is left of
/// the 322 pt equally, so the rule, the strip and the footer keep one rhythm
/// whether the status wraps or not.
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
        VStack(alignment: .leading, spacing: 0) {
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

            HStack(alignment: .center, spacing: 16) {
                SignalRing(
                    presentation: primary,
                    size: 104,
                    numeralSize: 24,
                    showsBudgetInside: true
                )
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 6) {
                        LedgerEyebrow(presentation: primary)
                        // 16 pt: "At least 80% of budget" fits the 186 pt
                        // column on one line, where 17 pt did not and was
                        // shrunk to its floor. Longer readings wrap.
                        StatusLine(
                            presentation: primary,
                            text: WidgetStyle.status(primary),
                            size: 16,
                            weight: .bold,
                            color: WidgetStyle.statusColor(primary),
                            lines: 2,
                            minimumScale: 0.75
                        )
                        if let line = streak.text {
                            Text(line).modifier(DetailLine())
                        }
                    }
                    .accessibilityElement(children: .combine)
                    if let secondary {
                        Hairline()
                            .padding(.vertical, 4)
                        SecondaryLedgerRow(presentation: secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 12)
            // The outer stack shares its height out among its rows before the
            // spacers claim the rest; without this the column is measured
            // short and its status scales down instead of wrapping.
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)
            Hairline()
            Spacer(minLength: 12)

            WeekCrossingStrip(summary: summary, ledger: primary.ledger)

            Spacer(minLength: 12)
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
            stamp: content.stamp,
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
