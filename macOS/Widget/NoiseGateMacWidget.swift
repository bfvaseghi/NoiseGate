import SwiftUI
import WidgetKit

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
    private func currentSnapshot() -> UsageSnapshot {
        var snapshot = UsageSnapshot.loadToday()
        if snapshot.monitoringIsActive,
           Date().timeIntervalSince(snapshot.updatedAt) > 45 {
            snapshot.monitoringIsActive = false
        }
        return snapshot
    }

    func placeholder(in context: Context) -> MacSnapshotEntry {
        MacSnapshotEntry(date: .now, snapshot: UsageSnapshot(
            distractionMinutes: 25,
            messagesMinutes: 40,
            distractionBudgetMinutes: 45,
            messagesBudgetMinutes: 60,
            distractionsConfigured: true,
            messagesConfigured: true,
            monitoringIsActive: true
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (MacSnapshotEntry) -> Void) {
        completion(MacSnapshotEntry(date: .now, snapshot: currentSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MacSnapshotEntry>) -> Void) {
        let entry = MacSnapshotEntry(date: .now, snapshot: currentSnapshot())
        let calendar = Calendar.current
        let now = Date()
        let refresh: Date
        if entry.snapshot.monitoringIsActive {
            let oneMinute = calendar.date(byAdding: .minute, value: 1, to: now)
                ?? now.addingTimeInterval(60)
            let staleDeadline = entry.snapshot.updatedAt.addingTimeInterval(46)
            refresh = max(now.addingTimeInterval(1), min(oneMinute, staleDeadline))
        } else {
            refresh = calendar.date(byAdding: .minute, value: 5, to: now)
                ?? now.addingTimeInterval(300)
        }
        let midnight = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: now) ?? now
        )
        completion(Timeline(entries: [entry], policy: .after(min(refresh, midnight))))
    }
}

struct NoiseGateMacWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NoiseGateMacWidget", provider: MacSnapshotProvider()) { entry in
            MacWidgetView(entry: entry)
                .containerBackground(NG.paper, for: .widget)
        }
        .configurationDisplayName("NoiseGate")
        .description("Distractions and Messages on this Mac. Everything else stays out.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MacWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MacSnapshotEntry

    private var snap: UsageSnapshot { entry.snapshot }

    private var distractionOver: Bool {
        snap.distractionsConfigured
            && snap.distractionMinutes >= snap.distractionBudgetMinutes
            && snap.distractionBudgetMinutes > 0
    }

    var body: some View {
        if family == .systemMedium {
            HStack(spacing: 16) {
                BudgetGauge(
                    title: "Distractions",
                    minutes: snap.distractionMinutes,
                    budgetMinutes: snap.distractionBudgetMinutes,
                    tint: NG.distraction,
                    isConfigured: snap.distractionsConfigured,
                    size: 90
                )
                BudgetGauge(
                    title: "Messages",
                    minutes: snap.messagesMinutes,
                    budgetMinutes: snap.messagesBudgetMinutes,
                    tint: NG.msg,
                    isConfigured: snap.messagesConfigured,
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
        } else {
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
                MacCompactLedgerRow(
                    title: "Distractions",
                    minutes: snap.distractionMinutes,
                    budget: snap.distractionBudgetMinutes,
                    tint: NG.distraction,
                    isConfigured: snap.distractionsConfigured
                )
                MacCompactLedgerRow(
                    title: "Messages",
                    minutes: snap.messagesMinutes,
                    budget: snap.messagesBudgetMinutes,
                    tint: NG.msg,
                    isConfigured: snap.messagesConfigured
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
        guard snap.monitoringIsActive else {
            return "Last tally. Open NoiseGate to resume tracking."
        }
        guard snap.distractionsConfigured else {
            return "Messages tracked separately."
        }
        if distractionOver {
            let over = snap.distractionMinutes - snap.distractionBudgetMinutes
            return over > 0
                ? "Distractions \(over.asHoursMinutes) over budget."
                : "Distraction budget reached."
        }
        return "\((snap.distractionBudgetMinutes - snap.distractionMinutes).asHoursMinutes) remaining."
    }

    private var compactStatus: String {
        guard snap.distractionsConfigured || snap.messagesConfigured else {
            return "Choose apps in NoiseGate"
        }
        return snap.monitoringIsActive
            ? "Everything else is excluded" : "Last tally · Open to resume"
    }
}

private struct MacCompactLedgerRow: View {
    let title: String
    let minutes: Int
    let budget: Int
    let tint: Color
    let isConfigured: Bool

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
                Text(isConfigured
                    ? "\(minutes.asHoursMinutes) / \(budget.asHoursMinutes)"
                    : "Not set")
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
        .accessibilityValue(isConfigured
            ? "\(minutes) minutes of \(budget)" : "Not configured")
    }
}
