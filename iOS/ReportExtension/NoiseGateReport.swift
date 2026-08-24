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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(minutes.asHoursMinutes)
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(overBudget ? .red : (kind == .noise ? .orange : .teal))
                Text("/ \(budgetMinutes.asHoursMinutes)")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if overBudget {
                    Text("OVER")
                        .font(.caption.weight(.black))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.red, in: Capsule())
                        .foregroundStyle(.white)
                }
            }

            ProgressView(value: fraction)
                .tint(overBudget ? .red : (kind == .noise ? .orange : .teal))
                .scaleEffect(y: 2, anchor: .center)

            if summary.topApps.isEmpty {
                Text(kind == .noise
                        ? "Zero noise so far. Keep it that way."
                        : "No messaging yet today.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(summary.topApps, id: \.name) { app in
                    HStack {
                        Text(app.name).font(.footnote.weight(.medium))
                        Spacer()
                        Text(Int(app.duration / 60).asHoursMinutes)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
