import Charts
import SwiftUI
import UserNotifications

struct MenuView: View {
    @EnvironmentObject private var model: MacModel

    private var distractionOver: Bool {
        model.distractionMinutesToday > model.config.distractionBudgetMinutes
            && model.config.distractionBudgetMinutes > 0
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
                    title: "Distractions",
                    minutes: model.distractionMinutesToday,
                    budgetMinutes: model.config.distractionBudgetMinutes,
                    tint: NG.distraction,
                    isConfigured: !model.distractionBundleIDs.isEmpty,
                    size: 96
                )
                BudgetGauge(
                    title: "Messages",
                    minutes: model.messagesMinutesToday,
                    budgetMinutes: model.config.messagesBudgetMinutes,
                    tint: NG.msg,
                    isConfigured: !model.messagesBundleIDs.isEmpty,
                    size: 96
                )
            }
            .frame(maxWidth: .infinity)

            if distractionOver {
                Label {
                    Text("Distractions are \((model.distractionMinutesToday - model.config.distractionBudgetMinutes).asHoursMinutes) over budget today. Resets at midnight.")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(NG.inkSoft)
                } icon: {
                    Image(systemName: "gauge.with.needle")
                        .foregroundStyle(NG.alarm)
                }
            }

            Label(model.trackingDetail, systemImage: trackingIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NG.inkSoft)

            MacWeekChart(records: model.weekRecords)

            Text("Only the apps you selected are counted. Everything else is untracked. Nothing is blocked.")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(NG.inkSoft)

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
        .frame(width: 300)
        .background(NG.paper)
    }

    private var trackingIcon: String {
        if !model.isSessionActive { return "lock" }
        if model.isUserIdle { return "pause.circle" }
        return "circle.fill"
    }
}

/// Receives one history snapshot so repeated chart subviews do not decode the
/// app-group history again during the same render.
private struct MacWeekChart: View {
    let records: [DayRecord]

    var body: some View {
        if records.count >= 2 {
            VStack(alignment: .leading, spacing: 6) {
                Text("DISTRACTIONS · \(records.count) RECORDED DAYS")
                    .font(.ngLabel(9))
                    .tracking(1.5)
                    .foregroundStyle(NG.inkSoft)
                Chart {
                    ForEach(records) { day in
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Minutes", day.distractionMinutes)
                        )
                        .foregroundStyle(
                            day.distractionReachedBudget ? NG.alarm : NG.distraction
                        )
                        .cornerRadius(3)
                    }
                    ForEach(records) { day in
                        LineMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Daily budget", day.distractionBudgetMinutes)
                        )
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(NG.inkSoft)
                    }
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
                title: "Distracting apps",
                subtitle: "Future time in these apps counts toward Distractions. Selecting one here moves future time out of Messages.",
                isOn: { model.distractionBundleIDs.contains($0) },
                toggle: model.toggleDistraction
            )
            .tabItem { Label("Distractions", systemImage: "waveform.slash") }
            AppPickerTab(
                title: "Messaging apps",
                subtitle: "Messages starts here by default. FaceTime and WhatsApp stay invisible unless you add them. Selecting an app here moves future time out of Distractions.",
                isOn: { model.messagesBundleIDs.contains($0) },
                toggle: model.toggleMessages
            )
            .tabItem { Label("Messages", systemImage: "message") }
        }
        .frame(width: 520, height: 460)
        .alert("Something went wrong", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
    }

    private var budgetsTab: some View {
        Form {
            Section("Daily budgets") {
                Stepper(value: Binding(
                    get: { model.config.distractionBudgetMinutes },
                    set: { model.adjustBudget(
                        \.distractionBudgetMinutes,
                        by: $0 - model.config.distractionBudgetMinutes
                    ) }
                ), in: 5...480, step: 5) {
                    LabeledContent(
                        "Distractions",
                        value: model.config.distractionBudgetMinutes.asHoursMinutes
                    )
                }
                Stepper(value: Binding(
                    get: { model.config.messagesBudgetMinutes },
                    set: { model.adjustBudget(
                        \.messagesBudgetMinutes,
                        by: $0 - model.config.messagesBudgetMinutes
                    ) }
                ), in: 5...480, step: 5) {
                    LabeledContent(
                        "Messages",
                        value: model.config.messagesBudgetMinutes.asHoursMinutes
                    )
                }
            }

            Section("Notifications") {
                Toggle("Allow checkpoint notifications", isOn: Binding(
                    get: { model.config.notificationsEnabled },
                    set: model.setNotificationsEnabled
                ))
                ForEach(BudgetConfig.nudgePercents, id: \.self) { percent in
                    Toggle("At \(percent)% of budget", isOn: Binding(
                        get: { model.config.notifyAt.contains(percent) },
                        set: { model.setNotification(at: percent, enabled: $0) }
                    ))
                    .disabled(!model.config.notificationsEnabled)
                }
                Toggle("Past budget (150% and 200%)", isOn: Binding(
                    get: { model.config.overtimeNotifications },
                    set: model.setOvertimeNotifications
                ))
                .disabled(!model.config.notificationsEnabled)
                if model.notificationStatus == .denied {
                    Text("Notifications are denied in System Settings. Tracking and widgets continue normally.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Tracker") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: model.setLaunchAtLogin
                ))
                Toggle("Show distraction minutes in the menu bar", isOn: Binding(
                    get: { model.config.showMinutesInMenuBar },
                    set: model.setShowMinutesInMenuBar
                ))
            }

            Section {
                Text("Time counts only while this Mac is active and an explicitly selected app is in front. Counting pauses after two minutes without input. Browser sites are not inspected. Nothing is blocked.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
                || $0.bundleID.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
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
                Text("Only time spent while an app is selected is counted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Rescan") { model.discoverApps() }
                    .controlSize(.small)
            }
        }
        .padding()
    }
}
