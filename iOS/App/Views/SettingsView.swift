import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: ScreenTimeModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PosterHeader(
                    eyebrow: "Your lines",
                    title: "BUDGETS.",
                    detail: "Friendly check-ins at 50, 80, and 100%. Nothing is ever blocked."
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
                    caption: "Tracked separately, on its own line."
                ) { adjust(\.messagesBudgetMinutes, by: $0) }

                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(NG.focus, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("How check-ins work")
                            .font(.system(size: 15.5, weight: .bold))
                            .foregroundStyle(NG.ink)
                        Text("A quiet note at 50%, 80%, and 100% of each budget, and a gentle check-in if a day runs far past the line. That's it — blocking is your other app's job.")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(NG.inkSoft)
                    }
                    Spacer()
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
