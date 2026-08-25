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
        DistractionsMonthReport { summary in
            WeekActivityView(summary: summary, kind: .distractions)
        }
        MessagesMonthReport { summary in
            WeekActivityView(summary: summary, kind: .messages)
        }
        DistractionsMoversReport { summary in
            MoversView(summary: summary, kind: .distractions)
        }
        DistractionsRhythmReport { summary in
            RhythmView(summary: summary, kind: .distractions)
        }
        MessagesRhythmReport { summary in
            RhythmView(summary: summary, kind: .messages)
        }
        CombinedReport { summary in
            CombinedView(summary: summary)
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
    static let distractionsMonth = Self("Distractions Month")
    static let messagesMonth = Self("Messages Month")
    static let distractionsMovers = Self("Distractions Movers")
    static let combined = Self("Combined")
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
            ? config.distractionBudget(on: .now) : config.messagesBudgetMinutes
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

// MARK: - Movers (what changed against its own baseline)

/// A budget is a number the owner picked, so meeting it proves nothing. This
/// compares the last seven days against the twenty-three before them, per app,
/// which is the one reading the owner did not choose in advance.
///
/// It has to live in the report extension: per-app exact usage is precisely
/// what Apple keeps inside this sandbox, so the comparison cannot be computed
/// anywhere the host could read it.
struct MoversSummary {
    struct Mover: Identifiable {
        let token: ApplicationToken
        /// Mean minutes per day across the recent window.
        let recentMinutesPerDay: Double
        /// Mean minutes per day across the days before it.
        let baselineMinutesPerDay: Double
        var id: ApplicationToken { token }

        var deltaMinutesPerDay: Double { recentMinutesPerDay - baselineMinutesPerDay }

        /// Nil when the baseline is too small for a percentage to mean
        /// anything — going from 20 seconds to a minute is not "+200%".
        var percentChange: Int? {
            guard baselineMinutesPerDay >= 1 else { return nil }
            let change = (recentMinutesPerDay - baselineMinutesPerDay)
                / baselineMinutesPerDay * 100
            return Int(change.rounded())
        }
    }

    var movers: [Mover] = []
    var recentDays = 7
    var baselineDays = HistoryStore.maxDays - 7
    /// False until there is any usage before the recent window to compare to.
    var hasBaseline = false
}

private func summarizeMovers(
    _ data: DeviceActivityResults<DeviceActivityData>,
    recentDays: Int = 7,
    windowDays: Int = HistoryStore.maxDays
) async -> MoversSummary {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: .now)
    let recentStart = calendar.date(
        byAdding: .day,
        value: -(recentDays - 1),
        to: today
    ) ?? today

    var recent: [ApplicationToken: TimeInterval] = [:]
    var baseline: [ApplicationToken: TimeInterval] = [:]
    for await deviceData in data {
        for await segment in deviceData.activitySegments {
            let day = calendar.startOfDay(for: segment.dateInterval.start)
            for await category in segment.categories {
                for await app in category.applications {
                    guard let token = app.application.token else { continue }
                    if day >= recentStart {
                        recent[token, default: 0] += app.totalActivityDuration
                    } else {
                        baseline[token, default: 0] += app.totalActivityDuration
                    }
                }
            }
        }
    }

    var summary = MoversSummary()
    summary.recentDays = recentDays
    summary.baselineDays = max(1, windowDays - recentDays)
    summary.hasBaseline = baseline.values.contains { $0 > 0 }

    let tokens = Set(recent.keys).union(baseline.keys)
    summary.movers = tokens
        .map { token in
            MoversSummary.Mover(
                token: token,
                recentMinutesPerDay: recent[token, default: 0] / 60
                    / Double(max(1, recentDays)),
                baselineMinutesPerDay: baseline[token, default: 0] / 60
                    / Double(summary.baselineDays)
            )
        }
        // Rank by how much the daily habit moved, in either direction. A
        // minute a day either way is noise, not a finding.
        .filter { abs($0.deltaMinutesPerDay) >= 1 }
        .sorted { abs($0.deltaMinutesPerDay) > abs($1.deltaMinutesPerDay) }
        .prefix(6)
        .map { $0 }
    return summary
}

struct DistractionsMoversReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .distractionsMovers
    let content: (MoversSummary) -> MoversView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> MoversSummary {
        await summarizeMovers(data)
    }
}

struct MoversView: View {
    let summary: MoversSummary
    let kind: ReportKind

    private var widest: Double {
        max(1, summary.movers.map { abs($0.deltaMinutesPerDay) }.max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if summary.movers.isEmpty {
                Text(summary.hasBaseline
                        ? "Nothing moved by more than a minute a day."
                        : "Not enough history yet to compare against.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NG.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(summary.movers) { mover in
                    MoverRow(mover: mover, widest: widest)
                }
                Text("Minutes per day over the last \(summary.recentDays) days against the \(summary.baselineDays) before them.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(NG.inkSoft)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MoverRow: View {
    let mover: MoversSummary.Mover
    let widest: Double

    private var isUp: Bool { mover.deltaMinutesPerDay > 0 }
    /// Up is the alarm colour and down is the Messages teal, matching how
    /// every other over/under reading in the app is coloured.
    private var tint: Color { isUp ? NG.alarm : NG.msg }
    private var share: Double { min(1, abs(mover.deltaMinutesPerDay) / widest) }

    private var change: String {
        if let percent = mover.percentChange {
            return "\(percent > 0 ? "+" : "")\(percent)%"
        }
        let delta = Int(mover.deltaMinutesPerDay.rounded())
        return "\(delta > 0 ? "+" : "")\(delta)m"
    }

    var body: some View {
        HStack(spacing: 8) {
            Label(mover.token)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(NG.ink)
                .lineLimit(1)
            Spacer(minLength: 6)

            // A diverging bar around a fixed centre, so "up" and "down" read
            // as directions rather than two unrelated lengths.
            ZStack {
                Capsule()
                    .fill(NG.line.opacity(0.7))
                    .frame(width: 64, height: 5)
                Rectangle()
                    .fill(NG.inkSoft.opacity(0.5))
                    .frame(width: 1, height: 7)
                Capsule()
                    .fill(tint)
                    .frame(width: max(3, 32 * share), height: 5)
                    .offset(x: isUp ? max(3, 32 * share) / 2 : -max(3, 32 * share) / 2)
            }
            .frame(width: 64, height: 7)
            .accessibilityHidden(true)

            Text(change)
                .font(.ngNumber(12.5))
                .foregroundStyle(tint)
                .frame(width: 48, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            isUp
                ? "up \(change), now \(Int(mover.recentMinutesPerDay.rounded())) minutes a day"
                : "down \(change), now \(Int(mover.recentMinutesPerDay.rounded())) minutes a day"
        )
    }
}

// MARK: - Combined (both totals as one number)

struct CombinedReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .combined
    let content: (ActivitySummary) -> CombinedView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> ActivitySummary {
        await summarize(data)
    }
}

/// Everything tracked, added up. The host passes the union of both token
/// sets, so this is the one place the two totals appear as a single figure —
/// the cards beneath it keep showing them apart.
struct CombinedView: View {
    let summary: ActivitySummary

    private var combinedBudget: Int {
        let config = BudgetConfig.load()
        return config.distractionBudget(on: .now) + config.messagesBudgetMinutes
    }

    private var reached: Bool {
        combinedBudget > 0 && summary.minutes >= combinedBudget
    }

    private var fraction: Double {
        combinedBudget > 0 ? min(1, Double(summary.minutes) / Double(combinedBudget)) : 0
    }

    private var tint: Color { reached ? NG.alarm : NG.ink }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summary.minutes.asHoursMinutes)
                    .font(.ngNumber(40))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text("OF \(combinedBudget.asHoursMinutes)")
                    .font(.ngLabel(10))
                    .tracking(1.4)
                    .foregroundStyle(NG.inkSoft)
                Spacer(minLength: 4)
                if summary.totalPickups > 0 {
                    Text("\(summary.totalPickups) PICKUPS")
                        .font(.ngLabel(10))
                        .tracking(1.4)
                        .foregroundStyle(NG.inkSoft)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(NG.line)
                    Capsule()
                        .fill(tint)
                        .frame(width: fraction == 0 ? 0 : max(8, geo.size.width * fraction))
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("All tracked time today")
        .accessibilityValue(
            "\(summary.minutes) minutes of a \(combinedBudget) minute combined budget"
                + (summary.totalPickups > 0 ? ", \(summary.totalPickups) pickups" : "")
        )
    }
}

// MARK: - Week view (exact 7-day chart, rendered inside the privacy sandbox)

struct WeekSummary {
    /// One entry per day in the window, oldest first, including zero-usage
    /// days. Seven for the week scene, thirty for the month scene.
    var days: [WeekDay] = []
    var totalMinutes = 0
    var totalPickups = 0
    /// Which apps the week actually went to, largest first. A daily total
    /// says the week was heavy; this says what made it heavy.
    var topApps: [ActivitySummary.AppUsage] = []

    var hasUsage: Bool { totalMinutes > 0 }

    struct WeekDay: Identifiable {
        let date: Date
        let minutes: Int
        let budgetMinutes: Int?
        var id: Date { date }
    }
}

private func summarizeWeek(
    _ data: DeviceActivityResults<DeviceActivityData>,
    kind: ReportKind,
    days dayCount: Int = 7
) async -> WeekSummary {
    // Segments arrive per device per day; merge across devices by day.
    var byDay: [Date: TimeInterval] = [:]
    var perApp: [ApplicationToken: (duration: TimeInterval, pickups: Int)] = [:]
    let calendar = Calendar.current
    for await deviceData in data {
        for await segment in deviceData.activitySegments {
            let day = calendar.startOfDay(for: segment.dateInterval.start)
            byDay[day, default: 0] += segment.totalActivityDuration
            for await category in segment.categories {
                for await app in category.applications {
                    guard let token = app.application.token else { continue }
                    var entry = perApp[token] ?? (0, 0)
                    entry.duration += app.totalActivityDuration
                    entry.pickups += app.numberOfPickups
                    perApp[token] = entry
                }
            }
        }
    }
    let today = calendar.startOfDay(for: .now)
    let todayKey = DayKey.today(today)
    let currentConfig = BudgetConfig.load()
    var history: [String: DayRecord] = [:]
    for record in HistoryStore.load() {
        history[record.dayKey] = record
    }
    let days = (0..<dayCount).compactMap { offset in
        calendar.date(byAdding: .day, value: offset - (dayCount - 1), to: today)
    }
    var summary = WeekSummary()
    summary.days = days.map { date in
        let key = DayKey.today(date)
        let stored = history[key]
        let budget: Int?
        if key == todayKey {
            budget = kind == .distractions
                ? currentConfig.distractionBudget(on: date)
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

/// Thirty days is the whole history `HistoryStore` retains, so this is the
/// longest honest window the app can offer.
struct DistractionsMonthReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .distractionsMonth
    let content: (WeekSummary) -> WeekActivityView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> WeekSummary {
        await summarizeWeek(data, kind: .distractions, days: HistoryStore.maxDays)
    }
}

struct MessagesMonthReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .messagesMonth
    let content: (WeekSummary) -> WeekActivityView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> WeekSummary {
        await summarizeWeek(data, kind: .messages, days: HistoryStore.maxDays)
    }
}

struct WeekActivityView: View {
    let summary: WeekSummary
    let kind: ReportKind

    private var tint: Color { kind == .distractions ? NG.distraction : NG.msg }

    private var dayCount: Int { max(1, summary.days.count) }
    private var dailyAverage: Int { summary.totalMinutes / dayCount }

    /// Thirty narrow weekday initials would be unreadable, so a longer
    /// window labels weeks instead of days.
    private var isLongWindow: Bool { dayCount > 10 }

    /// Taken from the days themselves rather than from `BudgetConfig`, so the
    /// key cannot disagree with the bars it is describing — and so this stays
    /// off the cross-process store during a render.
    private var weekdayBudget: Int? {
        summary.days.last { !Calendar.current.isDateInWeekend($0.date) }?.budgetMinutes
    }

    private var weekendBudget: Int? {
        summary.days.last { Calendar.current.isDateInWeekend($0.date) }?.budgetMinutes
    }

    /// Says what the red part of each bar is measured from. Without it the
    /// split is just two colours.
    @ViewBuilder
    private var budgetKey: some View {
        if let weekday = weekdayBudget {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(NG.alarm)
                    .frame(width: 11, height: 11)
                Text(weekendBudget.map { $0 == weekday
                        ? "Red is time past \(weekday.asHoursMinutes)"
                        : "Red is time past \(weekday.asHoursMinutes) · \($0.asHoursMinutes) Sat & Sun" }
                    ?? "Red is time past \(weekday.asHoursMinutes)")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(NG.inkSoft)
            }
            .accessibilityElement(children: .combine)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summary.totalMinutes.asHoursMinutes)
                    .font(.ngNumber(34))
                    .foregroundStyle(NG.ink)
                VStack(alignment: .leading, spacing: 1) {
                    Text("TOTAL · AVG \(dailyAverage.asHoursMinutes)/DAY")
                        .font(.ngLabel(10))
                        .tracking(1.5)
                        .foregroundStyle(NG.inkSoft)
                    if summary.totalPickups > 0 {
                        Text("\(summary.totalPickups) PICKUPS")
                            .font(.ngLabel(10))
                            .tracking(1.5)
                            .foregroundStyle(NG.inkSoft)
                    }
                }
                Spacer()
            }

            if !summary.hasUsage {
                Text("No usage recorded in the last \(dayCount) days.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NG.inkSoft)
            } else {
                // Each bar is split at that day's own budget: the ledger
                // colour up to the target, alarm above it. The red part is
                // the overage drawn at its own size, so it needs no reference
                // line — and it steps with a weekend budget by itself. A
                // dashed budget line drew vertical risers between weekday and
                // weekend targets that read as an empty box over the weekend.
                Chart {
                    ForEach(summary.days) { day in
                        if let budget = day.budgetMinutes, day.minutes > budget {
                            BarMark(
                                x: .value("Day", day.date, unit: .day),
                                yStart: .value("Start", 0),
                                yEnd: .value("Budget", budget)
                            )
                            .foregroundStyle(tint)
                            BarMark(
                                x: .value("Day", day.date, unit: .day),
                                yStart: .value("Budget", budget),
                                yEnd: .value("Minutes", day.minutes)
                            )
                            .foregroundStyle(NG.alarm)
                            .cornerRadius(isLongWindow ? 2 : 4)
                        } else {
                            BarMark(
                                x: .value("Day", day.date, unit: .day),
                                y: .value("Minutes", day.minutes)
                            )
                            .foregroundStyle(tint)
                            .cornerRadius(isLongWindow ? 2 : 4)
                        }
                    }
                }
                .chartXAxis {
                    if isLongWindow {
                        AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        }
                    } else {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisValueLabel(format: .dateTime.weekday(.narrow))
                        }
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
                .frame(height: 118)

                budgetKey

                if !summary.topApps.isEmpty {
                    Divider()
                    VStack(spacing: 6) {
                        ForEach(summary.topApps) { app in
                            AppRow(
                                app: app,
                                share: summary.totalMinutes > 0
                                    ? app.duration / (Double(summary.totalMinutes) * 60)
                                    : 0,
                                tint: tint
                            )
                        }
                    }
                }
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
