import Charts
import DeviceActivity
import SwiftUI

/// Renders exact usage for the filter the host app passes in. Screen Time data
/// stays inside this sandboxed view — it can't be exported, which is why the
/// widget uses threshold floors instead. Two scenes, one per category, so each
/// can compare against its own budget and get loud about it.
@main
struct NoiseGateReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        NoiseReport { summary in
            LoudActivityView(summary: summary, kind: .noise)
        }
        MessagesReport { summary in
            LoudActivityView(summary: summary, kind: .messages)
        }
        NoiseWeekReport { summary in
            WeekActivityView(summary: summary, kind: .noise)
        }
        MessagesWeekReport { summary in
            WeekActivityView(summary: summary, kind: .messages)
        }
    }
}

struct ActivitySummary {
    var totalDuration: TimeInterval = 0
    var topApps: [(name: String, duration: TimeInterval)] = []
}

extension DeviceActivityReport.Context {
    static let noise = Self("Noise")
    static let messages = Self("Messages")
    static let noiseWeek = Self("Noise Week")
    static let messagesWeek = Self("Messages Week")
}

enum ReportKind { case noise, messages }

private func summarize(
    _ data: DeviceActivityResults<DeviceActivityData>
) async -> ActivitySummary {
    var summary = ActivitySummary()
    var perApp: [String: TimeInterval] = [:]

    for await deviceData in data {
        for await segment in deviceData.activitySegments {
            summary.totalDuration += segment.totalActivityDuration
            for await category in segment.categories {
                for await app in category.applications {
                    let name = app.application.localizedDisplayName ?? "Unknown app"
                    perApp[name, default: 0] += app.totalActivityDuration
                }
            }
        }
    }

    summary.topApps = perApp
        .sorted { $0.value > $1.value }
        .prefix(3)
        .map { (name: $0.key, duration: $0.value) }
    return summary
}

struct NoiseReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .noise
    let content: (ActivitySummary) -> LoudActivityView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> ActivitySummary {
        await summarize(data)
    }
}

struct MessagesReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .messages
    let content: (ActivitySummary) -> LoudActivityView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> ActivitySummary {
        await summarize(data)
    }
}

struct LoudActivityView: View {
    let summary: ActivitySummary
    let kind: ReportKind

    private var budgetMinutes: Int {
        let config = BudgetConfig.load()
        return kind == .noise ? config.noiseBudgetMinutes : config.messagesBudgetMinutes
    }

    private var minutes: Int { Int(summary.totalDuration / 60) }
    private var overBudget: Bool { minutes >= budgetMinutes && budgetMinutes > 0 }
    private var fraction: Double {
        budgetMinutes > 0 ? min(1, Double(minutes) / Double(budgetMinutes)) : 0
    }

    private var tint: Color { kind == .noise ? NG.noise : NG.msg }
    private var barColor: Color { overBudget ? NG.alarm : tint }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(minutes.asHoursMinutes)
                    .font(.ngNumber(46))
                    .foregroundStyle(overBudget ? NG.alarm : NG.ink)
                    .contentTransition(.numericText())
                Text("/ \(budgetMinutes.asHoursMinutes)")
                    .font(.ngLabel(13))
                    .tracking(1)
                    .foregroundStyle(NG.inkSoft)
                Spacer()
                if overBudget {
                    Text("OVER")
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
                        .frame(width: max(10, geo.size.width * fraction))
                }
            }
            .frame(height: 12)

            if summary.topApps.isEmpty {
                Text(kind == .noise
                        ? "No noise-app usage recorded today."
                        : "No messaging recorded today.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NG.inkSoft)
            } else {
                VStack(spacing: 5) {
                    ForEach(summary.topApps, id: \.name) { app in
                        HStack {
                            Circle().fill(tint).frame(width: 6, height: 6)
                            Text(app.name)
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
    /// One entry per day, oldest first; days with no usage are zero-filled
    /// by the view's chart domain.
    var days: [WeekDay] = []
    var totalMinutes = 0

    struct WeekDay: Identifiable {
        let date: Date
        let minutes: Int
        var id: Date { date }
    }
}

private func summarizeWeek(
    _ data: DeviceActivityResults<DeviceActivityData>
) async -> WeekSummary {
    // Segments arrive per device per day; merge across devices by day.
    var byDay: [Date: Int] = [:]
    let calendar = Calendar.current
    for await deviceData in data {
        for await segment in deviceData.activitySegments {
            let day = calendar.startOfDay(for: segment.dateInterval.start)
            byDay[day, default: 0] += Int(segment.totalActivityDuration / 60)
        }
    }
    var summary = WeekSummary()
    summary.days = byDay
        .sorted { $0.key < $1.key }
        .map { WeekSummary.WeekDay(date: $0.key, minutes: $0.value) }
    summary.totalMinutes = byDay.values.reduce(0, +)
    return summary
}

struct NoiseWeekReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .noiseWeek
    let content: (WeekSummary) -> WeekActivityView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> WeekSummary {
        await summarizeWeek(data)
    }
}

struct MessagesWeekReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .messagesWeek
    let content: (WeekSummary) -> WeekActivityView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> WeekSummary {
        await summarizeWeek(data)
    }
}

struct WeekActivityView: View {
    let summary: WeekSummary
    let kind: ReportKind

    private var tint: Color { kind == .noise ? NG.noise : NG.msg }

    private var budgetMinutes: Int {
        let config = BudgetConfig.load()
        return kind == .noise ? config.noiseBudgetMinutes : config.messagesBudgetMinutes
    }

    private var dailyAverage: Int {
        summary.days.isEmpty ? 0 : summary.totalMinutes / summary.days.count
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

            if summary.days.isEmpty {
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
                            day.minutes >= budgetMinutes && budgetMinutes > 0
                                ? NG.alarm : tint
                        )
                        .cornerRadius(4)
                    }
                    if budgetMinutes > 0 {
                        RuleMark(y: .value("Budget", budgetMinutes))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .foregroundStyle(NG.inkSoft)
                            .annotation(position: .topTrailing, alignment: .trailing) {
                                Text("BUDGET \(budgetMinutes.asHoursMinutes)")
                                    .font(.ngLabel(8.5))
                                    .tracking(1)
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
