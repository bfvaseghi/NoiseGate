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
    }
}

struct ActivitySummary {
    var totalDuration: TimeInterval = 0
    var topApps: [AppUsage] = []

    struct AppUsage {
        let token: ApplicationToken
        let duration: TimeInterval
    }
}

extension DeviceActivityReport.Context {
    static let distractions = Self("Distractions")
    static let messages = Self("Messages")
    static let distractionsWeek = Self("Distractions Week")
    static let messagesWeek = Self("Messages Week")
}

enum ReportKind { case distractions, messages }

private func summarize(
    _ data: DeviceActivityResults<DeviceActivityData>
) async -> ActivitySummary {
    var summary = ActivitySummary()
    var perApp: [ApplicationToken: TimeInterval] = [:]

    for await deviceData in data {
        for await segment in deviceData.activitySegments {
            summary.totalDuration += segment.totalActivityDuration
            for await category in segment.categories {
                for await app in category.applications {
                    if let token = app.application.token {
                        perApp[token, default: 0] += app.totalActivityDuration
                    }
                }
            }
        }
    }

    summary.topApps = perApp
        .sorted { $0.value > $1.value }
        .prefix(3)
        .map { ActivitySummary.AppUsage(token: $0.key, duration: $0.value) }
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

    private var minutes: Int { Int(summary.totalDuration / 60) }
    private var reachedBudget: Bool { minutes >= budgetMinutes && budgetMinutes > 0 }
    private var overBudget: Bool { minutes > budgetMinutes && budgetMinutes > 0 }
    private var fraction: Double {
        budgetMinutes > 0 ? min(1, Double(minutes) / Double(budgetMinutes)) : 0
    }

    private var tint: Color { kind == .distractions ? NG.distraction : NG.msg }
    private var barColor: Color { reachedBudget ? NG.alarm : tint }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(minutes.asHoursMinutes)
                    .font(.ngNumber(46))
                    .foregroundStyle(reachedBudget ? NG.alarm : NG.ink)
                    .contentTransition(.numericText())
                Text("/ \(budgetMinutes.asHoursMinutes)")
                    .font(.ngLabel(13))
                    .tracking(1)
                    .foregroundStyle(NG.inkSoft)
                Spacer()
                if reachedBudget {
                    Text(overBudget ? "OVER" : "REACHED")
                        .font(.ngLabel(10))
                        .tracking(2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(NG.alarm, in: Capsule())
                }
            }

            // Thick budget bar; turns red once the budget is reached.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(barColor.opacity(0.14))
                    Capsule()
                        .fill(barColor)
                        .frame(width: fraction == 0 ? 0 : max(10, geo.size.width * fraction))
                }
            }
            .frame(height: 12)

            if summary.totalDuration == 0 {
                Text(kind == .distractions
                        ? "No distracting-app usage recorded today."
                        : "No messaging recorded today.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NG.inkSoft)
            } else if summary.topApps.isEmpty {
                Text("No app breakdown is available for this selection.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NG.inkSoft)
            } else {
                VStack(spacing: 5) {
                    ForEach(summary.topApps, id: \.token) { app in
                        HStack {
                            Label(app.token)
                                .labelStyle(.titleAndIcon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(NG.ink)
                            Spacer()
                            Text(Int(app.duration / 60).asHoursMinutes)
                                .font(.ngNumber(13))
                                .foregroundStyle(NG.inkSoft)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
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
