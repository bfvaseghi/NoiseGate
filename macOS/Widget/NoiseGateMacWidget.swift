import WidgetKit
import SwiftUI

@main
struct NoiseGateMacWidgetBundle: WidgetBundle {
    var body: some Widget {
        NoiseGateMacWidget()
    }
}

struct MacSnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

struct MacSnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> MacSnapshotEntry {
        MacSnapshotEntry(date: .now, snapshot: UsageSnapshot(
            noiseMinutes: 25, messagesMinutes: 40,
            noiseBudgetMinutes: 45, messagesBudgetMinutes: 60
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (MacSnapshotEntry) -> Void) {
        completion(MacSnapshotEntry(date: .now, snapshot: UsageSnapshot.loadToday()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MacSnapshotEntry>) -> Void) {
        // The app reloads timelines when it persists; the scheduled refresh
        // catches drift, landing exactly at midnight when that comes first.
        let entry = MacSnapshotEntry(date: .now, snapshot: UsageSnapshot.loadToday())
        let calendar = Calendar.current
        let in5 = calendar.date(byAdding: .minute, value: 5, to: .now) ?? .now
        let midnight = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        completion(Timeline(entries: [entry], policy: .after(min(in5, midnight))))
    }
}

struct NoiseGateMacWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NoiseGateMacWidget", provider: MacSnapshotProvider()) { entry in
            MacWidgetView(entry: entry)
                .containerBackground(NG.paper, for: .widget)
        }
        .configurationDisplayName("NoiseGate")
        .description("Today's noise and Messages time on this Mac.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MacWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MacSnapshotEntry

    private var snap: UsageSnapshot { entry.snapshot }

    private var noiseOver: Bool {
        snap.noiseMinutes >= snap.noiseBudgetMinutes && snap.noiseBudgetMinutes > 0
    }

    var body: some View {
        if family == .systemMedium {
            HStack(spacing: 18) {
                gauges(size: 92)
                VStack(alignment: .leading, spacing: 6) {
                    Text("NOISEGATE")
                        .font(.ngLabel(10))
                        .tracking(2)
                        .foregroundStyle(noiseOver ? NG.alarm : NG.inkSoft)
                    Text(noiseOver
                            ? "Noise \((snap.noiseMinutes - snap.noiseBudgetMinutes).asHoursMinutes) over budget."
                            : "\((snap.noiseBudgetMinutes - snap.noiseMinutes).asHoursMinutes) of noise remaining.")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NG.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            gauges(size: 64)
        }
    }

    private func gauges(size: CGFloat) -> some View {
        HStack(spacing: 12) {
            BudgetGauge(
                title: "Noise",
                minutes: snap.noiseMinutes,
                budgetMinutes: snap.noiseBudgetMinutes,
                tint: NG.noise,
                size: size
            )
            BudgetGauge(
                title: "Msgs",
                minutes: snap.messagesMinutes,
                budgetMinutes: snap.messagesBudgetMinutes,
                tint: NG.msg,
                size: size
            )
        }
    }
}
