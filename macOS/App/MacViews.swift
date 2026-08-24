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

            if noiseOver {
                Text("YOU'RE OVER.")
                    .font(.ngDisplay(16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        ZStack {
                            NG.overBannerGradient
                            HazardStripes(opacity: 0.1, lineWidth: 6, gap: 12)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    )
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

            // Compact version of the iOS focus slab.
            Button {
                model.setFocus(!model.focusOn)
            } label: {
                HStack {
                    Image(systemName: model.focusOn ? "moon.fill" : "moon")
                        .font(.system(size: 14, weight: .black))
                    Text(model.focusOn ? "FOCUSED — TAP TO END" : "FOCUS NOW")
                        .font(.ngLabel(11))
                        .tracking(1.5)
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    model.focusOn ? AnyShapeStyle(NG.focusGradient) : AnyShapeStyle(NG.ink),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
            .buttonStyle(.plain)

            if model.enforcementActive {
                Text(model.focusOn
                        ? "Noise apps are hidden while Focus is on."
                        : model.inQuietHours
                            ? "Quiet hours — noise apps are hidden."
                            : "Noise budget spent — noise apps are hidden.")
                    .font(.system(size: 11, weight: .semibold))
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
                subtitle: "Budgeted, nudged, and hidden when you're over. Social media lives here.",
                isOn: { model.noiseBundleIDs.contains($0) },
                toggle: model.toggleNoise
            )
            .tabItem { Label("Noise", systemImage: "waveform.slash") }
            AppPickerTab(
                title: "Messaging apps",
                subtitle: "Tracked separately with their own budget. Nudged, never blocked.",
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
                Toggle("Hide noise apps at 100%", isOn: $model.config.blockNoiseAtBudget)
                Toggle("Quiet hours", isOn: $model.config.quietHoursEnabled)
                if model.config.quietHoursEnabled {
                    quietHoursPickers
                }
            } footer: {
                Text("Nudges arrive at 50%, 80%, and 100% of each budget. Time only counts while you're actually at the keyboard — idle time is ignored.")
            }
        }
        .formStyle(.grouped)
    }

    private var quietHoursPickers: some View {
        Group {
            Picker("From", selection: $model.config.quietStartMinutes) {
                ForEach(0..<48, id: \.self) { halfHour in
                    Text(String(format: "%02d:%02d", halfHour / 2, (halfHour % 2) * 30))
                        .tag(halfHour * 30)
                }
            }
            Picker("Until", selection: $model.config.quietEndMinutes) {
                ForEach(0..<48, id: \.self) { halfHour in
                    Text(String(format: "%02d:%02d", halfHour / 2, (halfHour % 2) * 30))
                        .tag(halfHour * 30)
                }
            }
        }
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
