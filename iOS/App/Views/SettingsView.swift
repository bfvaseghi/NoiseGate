import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: ScreenTimeModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PosterHeader(
                    eyebrow: "The rules",
                    title: "BUDGETS.",
                    detail: "Nudges at 50 / 80 / 100% — then it stops being polite."
                )
                .padding(.top, 8)

                BudgetDial(
                    chip: "Noise", tint: NG.noise,
                    minutes: model.config.noiseBudgetMinutes,
                    caption: "Per day, across iPhone and iPad."
                ) { adjust(\.noiseBudgetMinutes, by: $0) }

                BudgetDial(
                    chip: "Messages", tint: NG.msg,
                    minutes: model.config.messagesBudgetMinutes,
                    caption: "Tracked separately. Never blocked."
                ) { adjust(\.messagesBudgetMinutes, by: $0) }

                RuleToggle(
                    title: "Block noise at 100%",
                    subtitle: "Budget spent → the wall goes up until midnight. Off = overtime nags instead.",
                    icon: "hand.raised.fill",
                    tint: NG.alarm,
                    isOn: $model.config.blockNoiseAtBudget
                )

                VStack(spacing: 0) {
                    RuleToggle(
                        title: "Quiet hours",
                        subtitle: "Noise apps are always blocked during the window. Overnight is fine.",
                        icon: "moon.stars.fill",
                        tint: NG.focus,
                        isOn: $model.config.quietHoursEnabled,
                        framed: false
                    )
                    if model.config.quietHoursEnabled {
                        Divider().padding(.vertical, 10)
                        HStack(spacing: 14) {
                            QuietTime(label: "From", selection: minutesBinding(\.quietStartMinutes))
                            QuietTime(label: "Until", selection: minutesBinding(\.quietEndMinutes))
                        }
                    }
                }
                .ngCard()

                Spacer(minLength: 96)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background(NG.paper.ignoresSafeArea())
        .onChange(of: model.config) { _, _ in
            model.applyChanges()
        }
    }

    private func adjust(_ keyPath: WritableKeyPath<BudgetConfig, Int>, by delta: Int) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            let value = model.config[keyPath: keyPath] + delta
            model.config[keyPath: keyPath] = min(480, max(5, value))
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

/// Big-numeral budget control: −/+ paddles around a huge rounded readout.
struct BudgetDial: View {
    let chip: String
    let tint: Color
    let minutes: Int
    let caption: String
    let adjust: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NGChip(text: chip, tint: tint)
            HStack {
                Paddle(symbol: "minus") { adjust(-5) }
                Spacer()
                VStack(spacing: 0) {
                    Text(minutes.asHoursMinutes)
                        .font(.ngNumber(44))
                        .foregroundStyle(NG.ink)
                        .contentTransition(.numericText())
                    Text("PER DAY")
                        .font(.ngLabel(10))
                        .tracking(2.5)
                        .foregroundStyle(NG.inkSoft)
                }
                Spacer()
                Paddle(symbol: "plus") { adjust(+5) }
            }
            Text(caption)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(NG.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ngCard()
        .sensoryFeedback(.increase, trigger: minutes)
    }

    private func Paddle(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .background(tint.opacity(0.13), in: Circle())
                .overlay(Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

struct RuleToggle: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    @Binding var isOn: Bool
    var framed: Bool = true

    var body: some View {
        let row = HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(NG.ink)
                Text(subtitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(NG.inkSoft)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(tint)
        }
        if framed {
            row.ngCard(padding: 16)
        } else {
            row
        }
    }
}

struct QuietTime: View {
    let label: String
    let selection: Binding<Date>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.ngLabel(10))
                .tracking(2)
                .foregroundStyle(NG.inkSoft)
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
