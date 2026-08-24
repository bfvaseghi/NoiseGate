import Charts
import DeviceActivity
import FamilyControls
import ManagedSettings
import SwiftUI

/// Renders exact usage for the filter the host app passes in. Screen Time data
/// stays inside this sandboxed view — it can't be exported, which is why the
/// widget uses threshold floors instead. Two scenes, one per category, so each
/// can compare against the budget that was active on that day.
@main
struct NoiseGateReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        DistractionsReport { summary in
            ActivityView(summary: summary, kind: .distractions)
        }
        MessagesReport { summary in
            ActivityView(summary: summary, kind: .messages)
        }
        DistractionsWeekReport { summary in
            WeekActivityView(summary: summary, kind: .distractions)
        }
        MessagesWeekReport { summary in
            WeekActivityView(summary: summary, kind: .messages)
        }
        DistractionsRhythmReport { summary in
            RhythmView(summary: summary, kind: .distractions)
        }
        MessagesRhythmReport { summary in
            RhythmView(summary: summary, kind: .messages)
        }
    }
}

struct ActivitySummary {
    var totalDuration: TimeInterval = 0
    var totalPickups: Int = 0
    var topApps: [AppUsage] = []

    struct AppUsage: Identifiable {
        let token: ApplicationToken
        let duration: TimeInterval
        let pickups: Int
        var id: ApplicationToken { token }
    }

    var minutes: Int { Int(totalDuration / 60) }

    /// Mean length of one visit — the number that separates a single sitting
    /// from repeated checking. Nil until there is something to divide.
    var averageSessionSeconds: Int? {
        guard totalPickups > 0, totalDuration > 0 else { return nil }
        return Int(totalDuration / Double(totalPickups))
    }
}

extension Int {
    /// Compact duration for session lengths, which are often under a minute.
    var asSessionLength: String {
        if self < 60 { return "\(self)s" }
        let minutes = self / 60, seconds = self % 60
        return seconds == 0 ? "\(minutes)m" : "\(minutes)m \(seconds)s"
    }
}

extension DeviceActivityReport.Context {
    static let distractions = Self("Distractions")
    static let messages = Self("Messages")
    static let distractionsWeek = Self("Distractions Week")
    static let messagesWeek = Self("Messages Week")
    static let distractionsRhythm = Self("Distractions Rhythm")
    static let messagesRhythm = Self("Messages Rhythm")
}

enum ReportKind { case distractions, messages }

private func summarize(
    _ data: DeviceActivityResults<DeviceActivityData>
) async -> ActivitySummary {
    var summary = ActivitySummary()
    var perApp: [ApplicationToken: (duration: TimeInterval, pickups: Int)] = [:]

    for await deviceData in data {
        for await segment in deviceData.activitySegments {
            summary.totalDuration += segment.totalActivityDuration
            for await category in segment.categories {
                for await app in category.applications {
                    guard let token = app.application.token else { continue }
                    var entry = perApp[token] ?? (0, 0)
                    entry.duration += app.totalActivityDuration
                    // How the time happened matters more than the total:
                    // twelve short pickups and one long sitting are different
                    // behaviours that a duration alone cannot tell apart.
                    entry.pickups += app.numberOfPickups
                    perApp[token] = entry
                }
            }
        }
    }

    summary.totalPickups = perApp.values.reduce(0) { $0 + $1.pickups }
    summary.topApps = perApp
        .sorted { $0.value.duration > $1.value.duration }
        .prefix(4)
        .map {
            ActivitySummary.AppUsage(
                token: $0.key,
                duration: $0.value.duration,
                pickups: $0.value.pickups
            )
        }
    return summary
}

struct DistractionsReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .distractions
    let content: (ActivitySummary) -> ActivityView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> ActivitySummary {
        await summarize(data)
    }
}

struct MessagesReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .messages
    let content: (ActivitySummary) -> ActivityView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> ActivitySummary {
        await summarize(data)
    }
}

struct ActivityView: View {
    let summary: ActivitySummary
    let kind: ReportKind

    private var budgetMinutes: Int {
        let config = BudgetConfig.load()
        return kind == .distractions
            ? config.distractionBudgetMinutes : config.messagesBudgetMinutes
    }

    private var minutes: Int { summary.minutes }
    private var reachedBudget: Bool { minutes >= budgetMinutes && budgetMinutes > 0 }
    private var overBudget: Bool { minutes > budgetMinutes && budgetMinutes > 0 }
    private var fraction: Double {
        budgetMinutes > 0 ? min(1, Double(minutes) / Double(budgetMinutes)) : 0
    }

    private var tint: Color { kind == .distractions ? NG.distraction : NG.msg }
    private var ringColor: Color { reachedBudget ? NG.alarm : tint }

    /// How far through the waking day it is, so the budget reading has
    /// somewhere to sit. Anchored at 07:00 because a budget spent before
    /// breakfast and one spent by midnight are not the same observation.
    private var dayFraction: Double {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now) ?? now
        let end = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: now) ?? now
        guard end > start else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            summaryRow
            appBreakdown
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryRow: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RingArc(
                    fraction: fraction,
                    color: ringColor,
                    size: 92,
                    isIndeterminate: summary.totalDuration == 0
                )
                VStack(spacing: 0) {
                    Text(minutes.asHoursMinutes)
                        .font(.ngNumber(21))
                        .foregroundStyle(summary.totalDuration == 0 ? NG.inkSoft : ringColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .contentTransition(.numericText())
                    Text("OF \(budgetMinutes.asHoursMinutes)")
                        .font(.ngLabel(10))
                        .tracking(0.8)
                        .foregroundStyle(NG.inkSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(20)
            }
            .frame(width: 92, height: 92)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(kind == .distractions ? "Distractions" : "Messages")
            .accessibilityValue(
                "\(minutes) minutes of a \(budgetMinutes) minute budget"
                    + (reachedBudget ? ", budget reached" : "")
            )

            VStack(alignment: .leading, spacing: 8) {
                if reachedBudget {
                    Text(overBudget ? "OVER BUDGET" : "BUDGET REACHED")
                        .font(.ngLabel(10))
                        .tracking(1.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(NG.alarm, in: Capsule())
                }

                // The behavioural read: a total says how long, pickups say
                // whether it arrived in one sitting or forty interruptions.
                if summary.totalDuration == 0 {
                    Text(kind == .distractions
                            ? "Nothing recorded yet today."
                            : "No messaging recorded yet today.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NG.inkSoft)
                } else {
                    if summary.totalPickups > 0 {
                        StatLine(
                            value: "\(summary.totalPickups)",
                            unit: summary.totalPickups == 1 ? "pickup" : "pickups"
                        )
                        if let seconds = summary.averageSessionSeconds {
                            StatLine(value: seconds.asSessionLength, unit: "average visit")
                        }
                    }
                    StatLine(
                        value: "\(Int((dayFraction * 100).rounded()))%",
                        unit: "through the day"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Per-app rows sit under the summary with a proportion bar each, so the
    /// split is legible without reading four numbers.
    @ViewBuilder
    private var appBreakdown: some View {
        if !summary.topApps.isEmpty, summary.totalDuration > 0 {
            Divider()
            VStack(spacing: 6) {
                ForEach(summary.topApps) { app in
                    AppRow(
                        app: app,
                        share: app.duration / summary.totalDuration,
                        tint: tint
                    )
                }
            }
        }
    }
}

/// One number with its unit, aligned so several stack into a tidy column.
private struct StatLine: View {
    let value: String
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value)
                .font(.ngNumber(15))
                .foregroundStyle(NG.ink)
            Text(unit)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NG.inkSoft)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AppRow: View {
    let app: ActivitySummary.AppUsage
    let share: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Label(app.token)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(NG.ink)
                .lineLimit(1)
            Spacer(minLength: 6)
            // Share of the day's total for this ledger.
            Capsule()
                .fill(tint.opacity(0.16))
                .frame(width: 46, height: 5)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(3, 46 * share), height: 5)
                }
                .accessibilityHidden(true)
            Text(Int(app.duration / 60).asHoursMinutes)
                .font(.ngNumber(12.5))
                .foregroundStyle(NG.inkSoft)
                .frame(width: 44, alignment: .trailing)
        }
        // Combine rather than ignore: the app's name is rendered by the
        // system from an opaque token, so we cannot supply a label ourselves
        // and ignoring the children would silence it.
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Week view (exact 7-day chart, rendered inside the privacy sandbox)

struct WeekSummary {
    /// Exactly seven entries, oldest first, including zero-usage days.
    var days: [WeekDay] = []
    var totalMinutes = 0

    var hasUsage: Bool { totalMinutes > 0 }

    struct WeekDay: Identifiable {
        let date: Date
        let minutes: Int
        let budgetMinutes: Int?
        var id: Date { date }
        var reachedBudget: Bool {
            budgetMinutes.map { minutes >= $0 } ?? false
        }
    }
}

private func summarizeWeek(
    _ data: DeviceActivityResults<DeviceActivityData>,
    kind: ReportKind
) async -> WeekSummary {
    // Segments arrive per device per day; merge across devices by day.
    var byDay: [Date: TimeInterval] = [:]
    let calendar = Calendar.current
    for await deviceData in data {
        for await segment in deviceData.activitySegments {
            let day = calendar.startOfDay(for: segment.dateInterval.start)
            byDay[day, default: 0] += segment.totalActivityDuration
        }
    }
    let today = calendar.startOfDay(for: .now)
    let todayKey = DayKey.today(today)
    let currentConfig = BudgetConfig.load()
    var history: [String: DayRecord] = [:]
    for record in HistoryStore.load() {
        history[record.dayKey] = record
    }
    let days = (0..<7).compactMap { offset in
        calendar.date(byAdding: .day, value: offset - 6, to: today)
    }
    var summary = WeekSummary()
    summary.days = days.map { date in
        let key = DayKey.today(date)
        let stored = history[key]
        let budget: Int?
        if key == todayKey {
            budget = kind == .distractions
                ? currentConfig.distractionBudgetMinutes
                : currentConfig.messagesBudgetMinutes
        } else if kind == .distractions {
            budget = stored?.distractionBudgetMinutes
        } else {
            budget = stored?.messagesBudgetMinutes
        }
        return WeekSummary.WeekDay(
            date: date,
            minutes: Int(byDay[date, default: 0] / 60),
            budgetMinutes: budget
        )
    }
    summary.totalMinutes = summary.days.reduce(0) { $0 + $1.minutes }
    return summary
}

struct DistractionsWeekReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .distractionsWeek
    let content: (WeekSummary) -> WeekActivityView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> WeekSummary {
        await summarizeWeek(data, kind: .distractions)
    }
}

struct MessagesWeekReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .messagesWeek
    let content: (WeekSummary) -> WeekActivityView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> WeekSummary {
        await summarizeWeek(data, kind: .messages)
    }
}

struct WeekActivityView: View {
    let summary: WeekSummary
    let kind: ReportKind

    private var tint: Color { kind == .distractions ? NG.distraction : NG.msg }

    private var dailyAverage: Int {
        summary.totalMinutes / 7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summary.totalMinutes.asHoursMinutes)
                    .font(.ngNumber(34))
                    .foregroundStyle(NG.ink)
                Text("TOTAL · AVG \(dailyAverage.asHoursMinutes)/DAY")
                    .font(.ngLabel(10))
                    .tracking(1.5)
                    .foregroundStyle(NG.inkSoft)
                Spacer()
            }

            if !summary.hasUsage {
                Text("No usage recorded in the last 7 days.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NG.inkSoft)
            } else {
                Chart {
                    ForEach(summary.days) { day in
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Minutes", day.minutes)
                        )
                        .foregroundStyle(
                            day.reachedBudget ? NG.alarm : tint
                        )
                        .cornerRadius(4)
                    }
                    ForEach(summary.days) { day in
                        if let budget = day.budgetMinutes {
                            LineMark(
                                x: .value("Day", day.date, unit: .day),
                                y: .value("Daily budget", budget)
                            )
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .foregroundStyle(NG.inkSoft)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let minutes = value.as(Int.self) {
                                Text("\(minutes)m").font(.system(size: 9))
                            }
                        }
                    }
                }
                .frame(height: 140)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Rhythm (hour-of-day pattern, exact, inside the privacy sandbox)

/// Which hours of the day the tracked ledger actually accumulates. Averaged
/// across the filtered range so one unusual evening doesn't read as a habit.
struct RhythmSummary {
    /// 24 buckets, index == hour of day, holding average minutes per day.
    var hourAverages: [Double] = Array(repeating: 0, count: 24)
    /// Number of distinct days observed, used to average the buckets.
    var dayCount: Int = 0
    var totalMinutes: Int = 0

    var peakHour: Int? {
        guard let maxValue = hourAverages.max(), maxValue > 0 else { return nil }
        return hourAverages.firstIndex(of: maxValue)
    }

    /// The contiguous 3-hour window carrying the most time, as a start hour.
    var peakWindowStart: Int? {
        guard hourAverages.contains(where: { $0 > 0 }) else { return nil }
        var best = 0
        var bestTotal = -1.0
        for start in 0..<24 {
            let total = (0..<3).reduce(0.0) { sum, offset in
                sum + hourAverages[(start + offset) % 24]
            }
            if total > bestTotal {
                bestTotal = total
                best = start
            }
        }
        return best
    }
}

private func summarizeRhythm(
    _ data: DeviceActivityResults<DeviceActivityData>
) async -> RhythmSummary {
    var buckets = Array(repeating: 0.0, count: 24)
    var days: Set<Date> = []
    var total = 0.0
    let calendar = Calendar.current

    // The host passes an `.hourly()` segment filter, so each segment is one
    // hour of one day; bucket by that hour and count the distinct days seen.
    for await deviceData in data {
        for await segment in deviceData.activitySegments {
            let start = segment.dateInterval.start
            let hour = calendar.component(.hour, from: start)
            let duration = segment.totalActivityDuration
            guard duration > 0 else { continue }
            buckets[hour] += duration
            total += duration
            days.insert(calendar.startOfDay(for: start))
        }
    }

    var summary = RhythmSummary()
    summary.dayCount = days.count
    let divisor = Double(max(1, days.count))
    summary.hourAverages = buckets.map { $0 / 60 / divisor }
    summary.totalMinutes = Int(total / 60)
    return summary
}

struct DistractionsRhythmReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .distractionsRhythm
    let content: (RhythmSummary) -> RhythmView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> RhythmSummary {
        await summarizeRhythm(data)
    }
}

struct MessagesRhythmReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .messagesRhythm
    let content: (RhythmSummary) -> RhythmView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> RhythmSummary {
        await summarizeRhythm(data)
    }
}

/// Hour-of-day columns with the peak window called out. Answers "when does
/// this happen?", which a daily total can never show.
struct RhythmView: View {
    let summary: RhythmSummary
    let kind: ReportKind

    private var tint: Color { kind == .distractions ? NG.distraction : NG.msg }

    private var peakLabel: String? {
        guard let start = summary.peakWindowStart,
              summary.totalMinutes > 0 else { return nil }
        let end = (start + 3) % 24
        return "\(RhythmView.hourLabel(start))–\(RhythmView.hourLabel(end))"
    }

    static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(.dateTime.hour())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let peakLabel {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(peakLabel)
                            .font(.ngNumber(26))
                            .foregroundStyle(NG.ink)
                        Text("BUSIEST WINDOW")
                            .font(.ngLabel(9.5))
                            .tracking(1.8)
                            .foregroundStyle(NG.inkSoft)
                    }
                } else {
                    Text("Not enough data yet")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NG.inkSoft)
                }
                Spacer()
                if summary.dayCount > 0, summary.totalMinutes > 0 {
                    Text("AVG OF \(summary.dayCount) DAY\(summary.dayCount == 1 ? "" : "S")")
                        .font(.ngLabel(9.5))
                        .tracking(1.5)
                        .foregroundStyle(NG.inkSoft)
                }
            }

            if summary.totalMinutes > 0 {
                RhythmBars(
                    values: summary.hourAverages,
                    tint: tint,
                    peakWindowStart: summary.peakWindowStart
                )
                .frame(height: 96)
                .accessibilityElement()
                .accessibilityLabel("Hour of day pattern")
                .accessibilityValue(
                    peakLabel.map { "Busiest between \($0)" } ?? "No usage recorded"
                )
            } else {
                Text("Once there are a few days of activity, this shows which hours it lands in.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NG.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 24 slim columns with 6-hour gridlines. Drawn directly rather than with
/// Charts so the hour axis stays legible at widget-card width.
struct RhythmBars: View {
    let values: [Double]
    let tint: Color
    let peakWindowStart: Int?

    private var maxValue: Double { max(values.max() ?? 1, 0.0001) }

    private func isPeak(_ hour: Int) -> Bool {
        guard let start = peakWindowStart else { return false }
        return (0..<3).contains { (start + $0) % 24 == hour }
    }

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let slot = geo.size.width / 24
                let barWidth = max(3, slot * 0.62)
                ZStack(alignment: .bottomLeading) {
                    // Quarter-day gridlines give the eye something to anchor on.
                    ForEach([6, 12, 18], id: \.self) { hour in
                        Rectangle()
                            .fill(NG.line)
                            .frame(width: 1)
                            .offset(x: slot * CGFloat(hour) + slot / 2)
                    }
                    ForEach(0..<24, id: \.self) { hour in
                        let height = geo.size.height * (values[hour] / maxValue)
                        Capsule()
                            .fill(isPeak(hour) ? tint : tint.opacity(0.28))
                            .frame(width: barWidth, height: max(2, height))
                            .offset(x: slot * CGFloat(hour) + (slot - barWidth) / 2)
                    }
                }
            }
            HStack(spacing: 0) {
                ForEach([0, 6, 12, 18], id: \.self) { hour in
                    Text(RhythmView.hourLabel(hour))
                        .font(.ngLabel(10))
                        .tracking(0.8)
                        .foregroundStyle(NG.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
