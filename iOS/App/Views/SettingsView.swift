import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: ScreenTimeModel

    private var quietStart: Binding<Date> {
        minutesBinding(\.quietStartMinutes)
    }
    private var quietEnd: Binding<Date> {
        minutesBinding(\.quietEndMinutes)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Daily budgets") {
                    Stepper(value: $model.config.noiseBudgetMinutes, in: 5...480, step: 5) {
                        LabeledContent("Noise", value: model.config.noiseBudgetMinutes.asHoursMinutes)
                    }
                    Stepper(value: $model.config.messagesBudgetMinutes, in: 5...480, step: 5) {
                        LabeledContent("Messages", value: model.config.messagesBudgetMinutes.asHoursMinutes)
                    }
                }

                Section {
                    Toggle("Block noise at 100%", isOn: $model.config.blockNoiseAtBudget)
                } footer: {
                    Text("When the noise budget is spent, the shield goes up for the rest of the day. You'll get nudges at 50%, 80%, and 100% either way.")
                }

                Section {
                    Toggle("Quiet hours", isOn: $model.config.quietHoursEnabled)
                    if model.config.quietHoursEnabled {
                        DatePicker("From", selection: quietStart, displayedComponents: .hourAndMinute)
                        DatePicker("Until", selection: quietEnd, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("Noise apps are always blocked during quiet hours. Overnight windows (e.g. 22:00 → 07:00) are fine.")
                }
            }
            .navigationTitle("Budgets")
            .onChange(of: model.config) { _, _ in
                model.applyChanges()
            }
        }
    }

    /// Bridges a minutes-from-midnight Int in the config to a DatePicker Date.
    private func minutesBinding(_ keyPath: WritableKeyPath<BudgetConfig, Int>) -> Binding<Date> {
        Binding<Date>(
            get: {
                let minutes = model.config[keyPath: keyPath]
                return Calendar.current.date(
                    bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now
                ) ?? .now
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                model.config[keyPath: keyPath] = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            }
        )
    }
}
