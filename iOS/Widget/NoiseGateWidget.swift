import SwiftUI
import WidgetKit

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
            distractionMinutes: 25,
            messagesMinutes: 40,
            distractionBudgetMinutes: 45,
            messagesBudgetMinutes: 60,
            distractionsConfigured: true,
            messagesConfigured: true,
            isFloor: true,
            monitoringIsActive: true
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: UsageSnapshot.loadToday()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
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
        .description("Distractions and Messages only. Everything else stays out.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

struct NoiseGateWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var snap: UsageSnapshot { entry.snapshot }

    private var distractionOver: Bool {
        snap.distractionsConfigured
            && snap.distractionMinutes >= snap.distractionBudgetMinutes
            && snap.distractionBudgetMinutes > 0
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: snap.distractionFraction) {
                Image(systemName: "waveform.slash")
            } currentValueLabel: {
                Text(checkpointText(
                    snap.distractionMinutes,
                    configured: snap.distractionsConfigured,
                    compact: true
                ))
            }
            .gaugeStyle(.accessoryCircular)
            .accessibilityLabel("Distractions")
            .accessibilityValue(accessibilityValue(
                minutes: snap.distractionMinutes,
                budget: snap.distractionBudgetMinutes,
                configured: snap.distractionsConfigured
            ))

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("NoiseGate", systemImage: "waveform.slash")
                    .font(.headline)
                Text("Distract. \(checkpointText(snap.distractionMinutes, configured: snap.distractionsConfigured)) / \(snap.distractionBudgetMinutes)m")
                    .font(.caption)
                Text("Messages \(checkpointText(snap.messagesMinutes, configured: snap.messagesConfigured)) / \(snap.messagesBudgetMinutes)m")
                    .font(.caption)
            }

        case .systemMedium:
            HStack(spacing: 16) {
                BudgetGauge(
                    title: "Distractions",
                    minutes: snap.distractionMinutes,
                    budgetMinutes: snap.distractionBudgetMinutes,
                    tint: NG.distraction,
                    isConfigured: snap.distractionsConfigured,
                    isFloor: snap.isFloor,
                    size: 90
                )
                BudgetGauge(
                    title: "Messages",
                    minutes: snap.messagesMinutes,
                    budgetMinutes: snap.messagesBudgetMinutes,
                    tint: NG.msg,
                    isConfigured: snap.messagesConfigured,
                    isFloor: snap.isFloor,
                    size: 90
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text("NOISEGATE")
                        .font(.ngLabel(10))
                        .tracking(2)
                        .foregroundStyle(distractionOver ? NG.alarm : NG.inkSoft)
                    Text(statusLine)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NG.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 2)

        default:
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("NOISEGATE")
                        .font(.ngLabel(10))
                        .tracking(2)
                        .foregroundStyle(NG.ink)
                    Spacer()
                    Image(systemName: "waveform.slash")
                        .foregroundStyle(NG.alarm)
                }
                CompactLedgerRow(
                    title: "Distractions",
                    minutes: snap.distractionMinutes,
                    budget: snap.distractionBudgetMinutes,
                    tint: NG.distraction,
                    isConfigured: snap.distractionsConfigured,
                    isFloor: snap.isFloor
                )
                CompactLedgerRow(
                    title: "Messages",
                    minutes: snap.messagesMinutes,
                    budget: snap.messagesBudgetMinutes,
                    tint: NG.msg,
                    isConfigured: snap.messagesConfigured,
                    isFloor: snap.isFloor
                )
                Text(compactStatus)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(NG.inkSoft)
            }
        }
    }

    private var statusLine: String {
        guard snap.distractionsConfigured || snap.messagesConfigured else {
            return "Choose apps in NoiseGate."
        }
        guard snap.monitoringIsActive else { return "Open NoiseGate to finish setup." }
        guard snap.distractionsConfigured else {
            return "Messages tracked separately."
        }
        if distractionOver {
            let over = snap.distractionMinutes - snap.distractionBudgetMinutes
            return over > 0
                ? "Distractions ≥\(over.asHoursMinutes) over budget."
                : "Distraction budget reached."
        }
        if snap.isFloor && snap.distractionMinutes == 0 {
            return "Below the first checkpoint."
        }
        return "≤\((snap.distractionBudgetMinutes - snap.distractionMinutes).asHoursMinutes) remaining."
    }

    private var compactStatus: String {
        guard snap.distractionsConfigured || snap.messagesConfigured else {
            return "Choose apps in NoiseGate"
        }
        return snap.monitoringIsActive
            ? "Everything else is excluded" : "Open NoiseGate to resume"
    }

    private func checkpointText(
        _ minutes: Int,
        configured: Bool,
        compact: Bool = false
    ) -> String {
        guard configured else { return compact ? "—" : "Not set" }
        if snap.isFloor && minutes == 0 { return compact ? "—" : "No checkpoint" }
        let value = compact ? "\(minutes)m" : minutes.asHoursMinutes
        return snap.isFloor && minutes > 0 ? "≥\(value)" : value
    }

    private func accessibilityValue(
        minutes: Int,
        budget: Int,
        configured: Bool
    ) -> String {
        guard configured else { return "Not configured" }
        if snap.isFloor && minutes == 0 { return "No checkpoint reached yet" }
        let qualifier = snap.isFloor && minutes > 0 ? "at least " : ""
        return "\(qualifier)\(minutes) minutes of a \(budget) minute budget"
    }
}

private struct CompactLedgerRow: View {
    let title: String
    let minutes: Int
    let budget: Int
    let tint: Color
    let isConfigured: Bool
    let isFloor: Bool

    private var fraction: Double {
        guard isConfigured, budget > 0 else { return 0 }
        return min(1, Double(minutes) / Double(budget))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(NG.ink)
                Spacer()
                Text(valueText)
                    .font(.ngNumber(10.5))
                    .foregroundStyle(NG.inkSoft)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.14))
                    Capsule().fill(tint)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    private var valueText: String {
        guard isConfigured else { return "Not set" }
        guard !isFloor || minutes > 0 else { return "No checkpoint" }
        return "\(isFloor ? "≥" : "")\(minutes.asHoursMinutes) / \(budget.asHoursMinutes)"
    }

    private var accessibilityValue: String {
        guard isConfigured else { return "Not configured" }
        guard !isFloor || minutes > 0 else { return "No checkpoint reached yet" }
        return "\(isFloor ? "at least " : "")\(minutes) minutes of \(budget)"
    }
}
