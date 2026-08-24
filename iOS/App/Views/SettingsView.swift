import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: ScreenTimeModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PosterHeader(
                    eyebrow: "Daily limits",
                    title: "BUDGETS.",
                    detail: "Notifications at 50%, 80%, and 100% of each budget."
                )
                .padding(.top, 8)

                BudgetDial(
                    chip: "Noise", tint: NG.noise,
                    minutes: model.config.noiseBudgetMinutes,
                    caption: "Daily limit for the apps on the noise list."
                ) { adjust(\.noiseBudgetMinutes, by: $0) }

                BudgetDial(
                    chip: "Messages", tint: NG.msg,
                    minutes: model.config.messagesBudgetMinutes,
                    caption: "Daily limit for Messages, tracked separately."
                ) { adjust(\.messagesBudgetMinutes, by: $0) }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(NG.focus, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text("Notifications")
                            .font(.system(size: 15.5, weight: .bold))
                            .foregroundStyle(NG.ink)
                        Spacer()
                    }
                    ForEach(BudgetConfig.nudgePercents, id: \.self) { pct in
                        Toggle("At \(pct)% of budget", isOn: notifyBinding(pct))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(NG.ink)
                            .tint(NG.focus)
                    }
                    Toggle("Past budget (150% and 200%)", isOn: $model.config.overtimeNotifications)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NG.ink)
                        .tint(NG.focus)
                    Text("Each notification is sent at most once per day, per category. Nothing is blocked.")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(NG.inkSoft)
                }
                .ngCard(padding: 16)

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

    private func notifyBinding(_ percent: Int) -> Binding<Bool> {
        Binding(
            get: { model.config.notifyAt.contains(percent) },
            set: { on in
                if on { model.config.notifyAt.insert(percent) }
                else { model.config.notifyAt.remove(percent) }
            }
        )
    }

    private func adjust(_ keyPath: WritableKeyPath<BudgetConfig, Int>, by delta: Int) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            let value = model.config[keyPath: keyPath] + delta
            model.config[keyPath: keyPath] = min(480, max(5, value))
        }
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
