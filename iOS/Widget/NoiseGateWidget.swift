import WidgetKit
import SwiftUI

@main
struct NoiseGateWidgetBundle: WidgetBundle {
    var body: some Widget {
        NoiseGateWidget()
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: UsageSnapshot(
            noiseMinutes: 25, messagesMinutes: 40,
            noiseBudgetMinutes: 45, messagesBudgetMinutes: 60, isFloor: true
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: UsageSnapshot.loadToday()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // The monitor extension reloads timelines when a threshold is crossed.
        // The scheduled refresh catches drift — and lands exactly at midnight
        // when that comes first, so the daily reset shows promptly.
        let entry = SnapshotEntry(date: .now, snapshot: UsageSnapshot.loadToday())
        let calendar = Calendar.current
        let in15 = calendar.date(byAdding: .minute, value: 15, to: .now) ?? .now
        let midnight = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        completion(Timeline(entries: [entry], policy: .after(min(in15, midnight))))
    }
}

struct NoiseGateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NoiseGateWidget", provider: SnapshotProvider()) { entry in
            NoiseGateWidgetView(entry: entry)
                .containerBackground(NG.paper, for: .widget)
        }
        .configurationDisplayName("NoiseGate")
        .description("Today's noise and Messages time against their budgets.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct NoiseGateWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var snap: UsageSnapshot { entry.snapshot }

    private var noiseOver: Bool {
        snap.noiseMinutes >= snap.noiseBudgetMinutes && snap.noiseBudgetMinutes > 0
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: snap.noiseFraction) {
                Image(systemName: "waveform.slash")
            } currentValueLabel: {
                Text("\(snap.noiseMinutes)m")
            }
            .gaugeStyle(.accessoryCircular)

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.slash")
                    Text("NoiseGate").font(.headline)
                }
                Text("Noise ≥\(snap.noiseMinutes)m / \(snap.noiseBudgetMinutes)m")
                    .font(.caption)
                Text("Msgs ≥\(snap.messagesMinutes)m / \(snap.messagesBudgetMinutes)m")
                    .font(.caption)
            }

        case .systemMedium:
            HStack(spacing: 18) {
                BudgetGauge(
                    title: "Noise",
                    minutes: snap.noiseMinutes,
                    budgetMinutes: snap.noiseBudgetMinutes,
                    tint: NG.noise,
                    isFloor: snap.isFloor,
                    size: 92
                )
                BudgetGauge(
                    title: "Msgs",
                    minutes: snap.messagesMinutes,
                    budgetMinutes: snap.messagesBudgetMinutes,
                    tint: NG.msg,
                    isFloor: snap.isFloor,
                    size: 92
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text("NOISEGATE")
                        .font(.ngLabel(10))
                        .tracking(2)
                        .foregroundStyle(noiseOver ? NG.alarm : NG.inkSoft)
                    Text(statusLine)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NG.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 2)

        default: // systemSmall — one ring reads better than two crammed ones
            BudgetGauge(
                title: "Noise",
                minutes: snap.noiseMinutes,
                budgetMinutes: snap.noiseBudgetMinutes,
                tint: NG.noise,
                isFloor: snap.isFloor,
                size: 96
            )
        }
    }

    private var statusLine: String {
        if noiseOver {
            let over = snap.noiseMinutes - snap.noiseBudgetMinutes
            return over > 0
                ? "Noise ≥\(over.asHoursMinutes) over budget."
                : "Noise budget reached."
        }
        return "≤\((snap.noiseBudgetMinutes - snap.noiseMinutes).asHoursMinutes) of noise remaining."
    }
}
