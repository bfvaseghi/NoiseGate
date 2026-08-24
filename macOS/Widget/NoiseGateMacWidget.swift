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
                    ZStack {
                        NG.alarmGradient
                        HazardStripes(opacity: 0.08)
                    }
                }
                .environment(\.colorScheme, .dark)
        } else {
            content
                .containerBackground(NG.paper, for: .widget)
        }
    }

    private var content: some View {
        HStack(spacing: 14) {
            BudgetGauge(
                title: "Noise",
                minutes: snap.noiseMinutes,
                budgetMinutes: snap.noiseBudgetMinutes,
                tint: NG.noise,
                size: family == .systemMedium ? 92 : 64
            )
            BudgetGauge(
                title: "Msgs",
                minutes: snap.messagesMinutes,
                budgetMinutes: snap.messagesBudgetMinutes,
                tint: NG.msg,
                size: family == .systemMedium ? 92 : 64
            )
            if family == .systemMedium {
                VStack(alignment: .leading, spacing: 7) {
                    if noiseOver {
                        Text("YOU'RE\nOVER.")
                            .font(.ngDisplay(26))
                            .lineSpacing(-2)
                    } else {
                        Label(
                            snap.focusActive ? "Focus on" : "Focus off",
                            systemImage: snap.focusActive ? "moon.fill" : "moon"
                        )
                        .font(.ngLabel(11))
                        .tracking(1)
                        .foregroundStyle(snap.focusActive ? NG.focus : .secondary)
                    }
                    Text(noiseOver
                            ? "OVER by \((snap.noiseMinutes - snap.noiseBudgetMinutes).asHoursMinutes). You know what to do."
                            : "\((snap.noiseBudgetMinutes - snap.noiseMinutes).asHoursMinutes) of noise left.")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(noiseOver ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
