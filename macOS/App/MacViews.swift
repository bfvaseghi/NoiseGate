import Charts
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var model: MacModel

    private var noiseOver: Bool {
        model.noiseMinutesToday >= model.config.noiseBudgetMinutes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text("NOISEGATE")
                    .font(.ngLabel(10))
                    .tracking(2.5)
                    .foregroundStyle(NG.alarm)
                Text("TODAY.")
                    .font(.ngDisplay(30))
                    .foregroundStyle(NG.ink)
            }

            HStack(spacing: 18) {
                BudgetGauge(
                    title: "Noise",
                    minutes: model.noiseMinutesToday,
                    budgetMinutes: model.config.noiseBudgetMinutes,
                    tint: NG.noise,
                    size: 96
                )
                BudgetGauge(
                    title: "Messages",
                    minutes: model.messagesMinutesToday,
                    budgetMinutes: model.config.messagesBudgetMinutes,
                    tint: NG.msg,
                    size: 96
                )
            }
            .frame(maxWidth: .infinity)

            if noiseOver {
                Label {
                    Text("Noise is \((model.noiseMinutesToday - model.config.noiseBudgetMinutes).asHoursMinutes) over budget today. Resets at midnight.")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(NG.inkSoft)
                } icon: {
                    Image(systemName: "gauge.with.needle")
                        .foregroundStyle(NG.alarm)
                }
            } else {
                Text("Only listed apps are counted. Nothing is blocked.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NG.inkSoft)
            }

            MacWeekChart(
                records: model.weekRecords,
                budgetMinutes: model.config.noiseBudgetMinutes
            )

            Divider()

            HStack {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                Spacer()
                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 280)
        .background(NG.paper)
    }
}

/// 7-day noise mini chart for the menu popover. Takes the records once so the
/// model's computed history isn't rebuilt per subview access.
struct MacWeekChart: View {
    let records: [DayRecord]
    let budgetMinutes: Int

    var body: some View {
        // One day of data isn't a trend yet.
        if records.count >= 2 {
            VStack(alignment: .leading, spacing: 6) {
                Text("NOISE · LAST \(records.count) DAYS")
                    .font(.ngLabel(9))
                    .tracking(1.5)
                    .foregroundStyle(NG.inkSoft)
                Chart {
                    ForEach(records) { day in
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Minutes", day.noiseMinutes)
                        )
                        .foregroundStyle(day.noiseReachedBudget ? NG.alarm : NG.noise)
                        .cornerRadius(3)
                    }
                    RuleMark(y: .value("Budget", budgetMinutes))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(NG.inkSoft)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 64)
            }
        }
    }
}

struct MacSettingsView: View {
    @EnvironmentObject private var model: MacModel

    var body: some View {
        TabView {
            budgetsTab
                .tabItem { Label("Budgets", systemImage: "slider.horizontal.3") }
            AppPickerTab(
                title: "Noise apps",
                subtitle: "Apps tracked against the noise budget. Toggle off to pause tracking.",
                isOn: { model.noiseBundleIDs.contains($0) },
                toggle: model.toggleNoise
            )
            .tabItem { Label("Noise", systemImage: "waveform.slash") }
            AppPickerTab(
                title: "Messaging apps",
                subtitle: "Apps tracked against the Messages budget. Default: Messages only — FaceTime and WhatsApp are only tracked if you add them.",
                isOn: { model.messagesBundleIDs.contains($0) },
                toggle: model.toggleMessages
            )
            .tabItem { Label("Messages", systemImage: "message") }
        }
        .frame(width: 480, height: 420)
    }

    private var budgetsTab: some View {
        Form {
            Section("Daily budgets") {
                Stepper(value: $model.config.noiseBudgetMinutes, in: 5...480, step: 5) {
                    LabeledContent("Noise", value: model.config.noiseBudgetMinutes.asHoursMinutes)
                }
                Stepper(value: $model.config.messagesBudgetMinutes, in: 5...480, step: 5) {
                    LabeledContent("Messages", value: model.config.messagesBudgetMinutes.asHoursMinutes)
                }
            }
            Section("Notifications") {
                ForEach(BudgetConfig.nudgePercents, id: \.self) { pct in
                    Toggle("At \(pct)% of budget", isOn: notifyBinding(pct))
                }
                Toggle("Past budget (150% and 200%)", isOn: $model.config.overtimeNotifications)
            }
            Section("Menu bar") {
                Toggle("Show today's noise minutes", isOn: $model.config.showMinutesInMenuBar)
            }
            Section {
                Text("Each notification is sent at most once per day, per category. Time only counts while the Mac is in use; after 2 minutes without input, counting stops. Nothing is blocked.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func notifyBinding(_ percent: Int) -> Binding<Bool> {
        Binding(
            get: { model.config.notifyAt.contains(percent) },
            set: { on in
                if on { model.config.notifyAt.insert(percent) }
                else { model.config.notifyAt.remove(percent) }
            }
        )
    }
}

struct AppPickerTab: View {
    @EnvironmentObject private var model: MacModel
    let title: String
    let subtitle: String
    let isOn: (String) -> Bool
    let toggle: (String) -> Void
    @State private var search = ""

    private var filtered: [DiscoveredApp] {
        guard !search.isEmpty else { return model.installedApps }
        return model.installedApps.filter {
            $0.name.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Search apps", text: $search)
                .textFieldStyle(.roundedBorder)
            List(filtered) { app in
                Toggle(isOn: Binding(
                    get: { isOn(app.bundleID) },
                    set: { _ in toggle(app.bundleID) }
                )) {
                    VStack(alignment: .leading) {
                        Text(app.name)
                        Text(app.bundleID)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            HStack {
                Button("Rescan installed apps") { model.discoverApps() }
                    .controlSize(.small)
                Spacer()
            }
        }
        .padding()
    }
}
