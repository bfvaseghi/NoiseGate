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
        let entry = MacSnapshotEntry(date: .now, snapshot: UsageSnapshot.loadToday())
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct NoiseGateMacWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NoiseGateMacWidget", provider: MacSnapshotProvider()) { entry in
            MacWidgetView(entry: entry)
        }
        .configurationDisplayName("NoiseGate")
        .description("Today's noise and messaging time on this Mac.")
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
        if noiseOver {
            content
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [.red, Color(red: 0.6, green: 0, blue: 0)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .environment(\.colorScheme, .dark)
        } else {
            content
                .containerBackground(.background, for: .widget)
        }
    }

    private var content: some View {
        HStack(spacing: 14) {
            BudgetGauge(
                title: "Noise",
                minutes: snap.noiseMinutes,
                budgetMinutes: snap.noiseBudgetMinutes,
                tint: .orange
            )
            BudgetGauge(
                title: "Messages",
                minutes: snap.messagesMinutes,
                budgetMinutes: snap.messagesBudgetMinutes,
                tint: .teal
            )
            if family == .systemMedium {
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        snap.focusActive ? "Focus on" : "Focus off",
                        systemImage: snap.focusActive ? "moon.fill" : "moon"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(snap.focusActive ? Color.indigo : .secondary)
                    Text(noiseOver
                            ? "OVER by \((snap.noiseMinutes - snap.noiseBudgetMinutes).asHoursMinutes). You know what to do."
                            : "\((snap.noiseBudgetMinutes - snap.noiseMinutes).asHoursMinutes) of noise left.")
                        .font(noiseOver ? .caption2.weight(.bold) : .caption2)
                        .foregroundStyle(noiseOver ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
