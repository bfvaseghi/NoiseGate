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
                    Text("Past your noise line for today — tomorrow resets the count.")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(NG.inkSoft)
                } icon: {
                    Image(systemName: "gauge.with.needle")
                        .foregroundStyle(NG.alarm)
                }
            } else {
                Text("Only flagged apps are counted. Nothing is ever blocked.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NG.inkSoft)
            }

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

struct MacSettingsView: View {
    @EnvironmentObject private var model: MacModel

    var body: some View {
        TabView {
            budgetsTab
                .tabItem { Label("Budgets", systemImage: "slider.horizontal.3") }
            AppPickerTab(
                title: "Noise apps",
                subtitle: "The distracting stuff. Tracked and budgeted — never blocked. Toggle off to pause.",
                isOn: { model.noiseBundleIDs.contains($0) },
                toggle: model.toggleNoise
            )
            .tabItem { Label("Noise", systemImage: "waveform.slash") }
            AppPickerTab(
                title: "Messaging apps",
                subtitle: "Just Messages, ideally — FaceTime and WhatsApp are real conversation, leave them out.",
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
            Section {
                Text("Friendly check-ins at 50%, 80%, and 100% of each budget, plus a gentle note if a day runs far past the line. Time only counts while you're actually at the keyboard — idle time is ignored. Nothing is ever blocked.")
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
