import Charts
import SwiftUI
import UserNotifications

struct MenuView: View {
    @EnvironmentObject private var model: MacModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SignalHeader(title: "Today", badge: "This Mac")
            ledger(title: "Distractions", minutes: model.distractionMinutesToday,
                   budget: model.todayDistractionBudget, tint: NG.distraction,
                   configured: !model.distractionBundleIDs.isEmpty, isInstrument: true)
            ledger(title: "Messages", minutes: model.messagesMinutesToday,
                   budget: model.config.messagesBudgetMinutes, tint: NG.msg,
                   configured: !model.messagesBundleIDs.isEmpty)
            Label(model.trackingDetail,
                  systemImage: !model.isSessionActive ? "lock" : (model.isUserIdle ? "pause.circle" : "circle.fill"))
                .font(.caption).foregroundStyle(NG.inkSoft)
            MacWeekChart(records: model.weekRecords)
            Divider()
            HStack {
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(20).frame(width: 340).background(NG.paper)
    }

    private func ledger(title: String, minutes: Int, budget: Int,
                        tint: Color, configured: Bool, isInstrument: Bool = false) -> some View {
        let ink = isInstrument ? NG.instrumentInk : NG.ink
        let soft = isInstrument ? NG.instrumentSoft : NG.inkSoft
        let accent = isInstrument ? NG.instrumentAccent : tint
        let alarm = isInstrument ? NG.instrumentAlarm : NG.alarm
        return VStack(alignment: .leading, spacing: 12) {
            SignalLabel(title: title, tint: accent, foreground: ink)
            if configured {
                HStack(alignment: .firstTextBaseline) {
                    SignalTimeReadout(minutes: minutes, size: isInstrument ? 60 : 32)
                        .foregroundStyle(minutes >= budget ? alarm : ink)
                    Spacer()
                    Text(minutes >= budget
                         ? (minutes == budget ? "Target reached" : "\((minutes - budget).asHoursMinutes) over")
                         : "\((budget - minutes).asHoursMinutes) left")
                        .font(.ngMono(10)).foregroundStyle(soft)
                }
                if isInstrument {
                    SignalMeter(minutes: minutes, budget: budget,
                                tint: minutes >= budget ? alarm : accent, inverted: true)
                } else {
                    SignalSegments(fraction: Double(minutes) / Double(max(1, budget)),
                                   tint: minutes >= budget ? alarm : accent, height: 8)
                    Text("Daily target · \(budget.asHoursMinutes)").font(.ngMono(10)).foregroundStyle(soft)
                }
            } else {
                SettingsLink { Text("Choose apps").font(.subheadline) }
                    .tint(accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .background(isInstrument ? NG.instrument : NG.card,
                    in: RoundedRectangle(cornerRadius: isInstrument ? 5 : 0))
        .overlay(alignment: .top) {
            if !isInstrument { Rectangle().fill(NG.line).frame(height: 1) }
        }
    }
}

/// Receives one history snapshot so repeated chart subviews do not decode the
/// app-group history again during the same render.
private struct MacWeekChart: View {
    let records: [DayRecord]

    var body: some View {
        if records.count >= 2 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Distractions · 7 days")
                    .font(.ngLabel(10))
                    .foregroundStyle(NG.inkSoft)
                // Split at each day's own budget rather than drawing a
                // dashed reference line over the bars: the red part is the
                // overage at its own size, and it steps with a weekend budget
                // without a line having to jump.
                Chart {
                    ForEach(records) { day in
                        if day.distractionMinutes > day.distractionBudgetMinutes {
                            BarMark(
                                x: .value("Day", day.date, unit: .day),
                                yStart: .value("Start", 0),
                                yEnd: .value("Budget", day.distractionBudgetMinutes)
                            )
                            .foregroundStyle(NG.distraction)
                            BarMark(
                                x: .value("Day", day.date, unit: .day),
                                yStart: .value("Budget", day.distractionBudgetMinutes),
                                yEnd: .value("Minutes", day.distractionMinutes)
                            )
                            .foregroundStyle(NG.alarm)
                            .cornerRadius(3)
                        } else {
                            BarMark(
                                x: .value("Day", day.date, unit: .day),
                                y: .value("Minutes", day.distractionMinutes)
                            )
                            .foregroundStyle(NG.distraction)
                            .cornerRadius(3)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 64)
                Text("Red shows time over that day’s target")
                    .font(.caption2).foregroundStyle(NG.inkSoft)
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
                subtitle: "Choose the apps to count as Distractions.",
                isOn: { model.distractionBundleIDs.contains($0) },
                toggle: model.toggleDistraction
            )
            .tabItem { Label("Distractions", systemImage: "waveform.slash") }
            AppPickerTab(
                title: "Messaging apps",
                subtitle: "Keep messaging time in its own total.",
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

            Section("Weekends") {
                Toggle("Different Distractions target", isOn: Binding(
                    get: { model.config.weekendBudgetsEnabled }, set: model.setWeekendBudgets
                ))
                if model.config.weekendBudgetsEnabled {
                    Stepper(value: Binding(
                        get: { model.config.weekendDistractionBudgetMinutes },
                        set: { model.adjustBudget(\.weekendDistractionBudgetMinutes,
                                                  by: $0 - model.config.weekendDistractionBudgetMinutes) }
                    ), in: 5...480, step: 5) {
                        LabeledContent("Weekends", value: model.config.weekendDistractionBudgetMinutes.asHoursMinutes)
                    }
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
                Text("Counts selected apps while this Mac is active. Pauses after two minutes without input.")
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
    @State private var selectedOnly = false

    private var filtered: [DiscoveredApp] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.installedApps.filter {
            (!selectedOnly || isOn($0.bundleID)) && (query.isEmpty
                || $0.name.localizedCaseInsensitiveContains(query)
                || $0.bundleID.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField("Search apps", text: $search).textFieldStyle(.roundedBorder)
                Toggle("Selected", isOn: $selectedOnly).toggleStyle(.button)
            }
            List(filtered) { app in
                Toggle(isOn: Binding(
                    get: { isOn(app.bundleID) },
                    set: { _ in toggle(app.bundleID) }
                )) {
                    VStack(alignment: .leading) {
                        Text(app.name)
                        if app.name != app.bundleID && model.installedApps.contains(where: {
                            $0.name == app.name && $0.bundleID != app.bundleID
                        }) {
                            Text(app.bundleID).font(.caption2).foregroundStyle(NG.inkSoft)
                        }
                    }
                }
            }
            if filtered.isEmpty {
                Text(model.isDiscoveringApps ? "Finding apps…" : "No matching apps")
                    .font(.callout).foregroundStyle(NG.inkSoft)
            }
            HStack {
                Text("Changes apply to future time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(model.isDiscoveringApps ? "Scanning…" : "Rescan") { model.discoverApps() }
                    .disabled(model.isDiscoveringApps)
                    .controlSize(.small)
            }
        }
        .padding()
    }
}
