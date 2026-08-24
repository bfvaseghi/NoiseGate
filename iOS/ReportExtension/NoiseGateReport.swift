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
    }
}

struct ActivitySummary {
    var totalDuration: TimeInterval = 0
    var topApps: [(name: String, duration: TimeInterval)] = []
}

extension DeviceActivityReport.Context {
    static let noise = Self("Noise")
    static let messages = Self("Messages")
}

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
    enum Kind { case noise, messages }

    let summary: ActivitySummary
    let kind: Kind

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
