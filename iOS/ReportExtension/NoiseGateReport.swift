import DeviceActivity
import SwiftUI

/// Renders exact usage for whatever filter the host app passes in (the noise
/// selection or the messages selection). Screen Time data stays inside this
/// sandboxed view — it can't be exported, which is why the widget uses
/// threshold floors instead.
@main
struct NoiseGateReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TotalActivityReport { summary in
            TotalActivityView(summary: summary)
        }
    }
}

struct ActivitySummary {
    var totalDuration: TimeInterval = 0
    var topApps: [(name: String, duration: TimeInterval)] = []
}

extension DeviceActivityReport.Context {
    static let totalActivity = Self("Total Activity")
}

struct TotalActivityReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .totalActivity
    let content: (ActivitySummary) -> TotalActivityView

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
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
}

struct TotalActivityView: View {
    let summary: ActivitySummary

    private func format(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        return minutes.asHoursMinutes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(format(summary.totalDuration))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(summary.totalDuration > 0 ? .primary : .secondary)
            if summary.topApps.isEmpty {
                Text("Nothing yet today. Keep it that way.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(summary.topApps, id: \.name) { app in
                    HStack {
                        Text(app.name).font(.footnote)
                        Spacer()
                        Text(format(app.duration))
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
