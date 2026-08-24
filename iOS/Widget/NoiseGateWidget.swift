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
        // The monitor extension reloads timelines when a threshold is crossed;
        // the 15-minute refresh mainly catches the midnight rollover.
        let entry = SnapshotEntry(date: .now, snapshot: UsageSnapshot.loadToday())
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct NoiseGateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NoiseGateWidget", provider: SnapshotProvider()) { entry in
            NoiseGateWidgetView(entry: entry)
        }
        .configurationDisplayName("NoiseGate")
        .description("Today's noise and messaging budgets at a glance.")
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
        if noiseOver, family == .systemSmall || family == .systemMedium {
            content
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [.red, Color(red: 0.6, green: 0, blue: 0)],
                                   startPoint: .top, endPoint: .bottom)
                }
                // Dark scheme so text and gauges render light on the red slab.
                .environment(\.colorScheme, .dark)
        } else {
            content
                .containerBackground(.background, for: .widget)
        }
    }

    @ViewBuilder
    private var content: some View {
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
                    Image(systemName: snap.focusActive ? "moon.fill" : "waveform.slash")
                    Text(noiseOver ? "OVER BUDGET" : "NoiseGate")
                        .font(.headline.weight(noiseOver ? .black : .semibold))
                }
                Text("Noise ≥\(snap.noiseMinutes)m / \(snap.noiseBudgetMinutes)m")
                    .font(.caption)
                Text("Msgs ≥\(snap.messagesMinutes)m / \(snap.messagesBudgetMinutes)m")
                    .font(.caption)
            }

        case .systemMedium:
            HStack(spacing: 20) {
                gauges
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        snap.focusActive ? "Focus on" : "Focus off",
                        systemImage: snap.focusActive ? "moon.fill" : "moon"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(snap.focusActive ? Color.indigo : .secondary)
                    Text(statusLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 4)

        default: // systemSmall
            gauges
        }
    }

    private var gauges: some View {
        HStack(spacing: 14) {
            BudgetGauge(
                title: "Noise",
                minutes: snap.noiseMinutes,
                budgetMinutes: snap.noiseBudgetMinutes,
                tint: .orange,
                isFloor: snap.isFloor
            )
            BudgetGauge(
                title: "Messages",
                minutes: snap.messagesMinutes,
                budgetMinutes: snap.messagesBudgetMinutes,
                tint: .teal,
                isFloor: snap.isFloor
            )
        }
    }

    private var statusLine: String {
        if noiseOver {
            let over = snap.noiseMinutes - snap.noiseBudgetMinutes
            return over > 0
                ? "≥\(over.asHoursMinutes) OVER. You know what to do."
                : "Budget SPENT. You know what to do."
        }
        let left = snap.noiseBudgetMinutes - snap.noiseMinutes
        return "≤\(left.asHoursMinutes) of noise left today."
    }
}
