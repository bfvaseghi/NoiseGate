import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var model: ScreenTimeModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PosterHeader(
                    eyebrow: "Daily budgets",
                    title: "BUDGETS.",
                    detail: "Each ledger gets its own target and optional checkpoint nudges."
                )
                .padding(.top, 8)

                BudgetDial(
                    chip: "Distractions", tint: NG.distraction,
                    minutes: model.config.distractionBudgetMinutes,
                    caption: "Daily target for the distracting apps and sites you chose."
                ) { model.adjustBudget(\.distractionBudgetMinutes, by: $0) }

                BudgetDial(
                    chip: "Messages", tint: NG.msg,
                    minutes: model.config.messagesBudgetMinutes,
                    caption: "Daily target for Messages, tracked separately."
                ) { model.adjustBudget(\.messagesBudgetMinutes, by: $0) }

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
                    Toggle("Allow checkpoint notifications", isOn: Binding(
                        get: { model.config.notificationsEnabled },
                        set: model.setNotificationsEnabled
                    ))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NG.ink)
                    .tint(NG.focus)

                    ForEach(BudgetConfig.nudgePercents, id: \.self) { pct in
                        Toggle("At \(pct)% of budget", isOn: notifyBinding(pct))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(NG.ink)
                            .tint(NG.focus)
                            .disabled(!model.config.notificationsEnabled)
                    }
                    Toggle("Past budget (150% and 200%)", isOn: Binding(
                        get: { model.config.overtimeNotifications },
                        set: model.setOvertimeNotifications
                    ))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NG.ink)
                        .tint(NG.focus)
                        .disabled(!model.config.notificationsEnabled)
                    Group {
                        if model.notificationStatus == .denied {
                            Text("Notifications are denied in iPhone Settings. Tracking and widgets continue normally.")
                        } else {
                            Text("Each enabled nudge is sent at most once per day, per ledger. Nothing is blocked.")
                        }
                    }
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
    }

    private func notifyBinding(_ percent: Int) -> Binding<Bool> {
        Binding(
            get: { model.config.notifyAt.contains(percent) },
            set: { model.setNotification(at: percent, enabled: $0) }
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
                Paddle(
                    symbol: "minus",
                    accessibilityLabel: "Decrease \(chip) budget"
                ) { adjust(-5) }
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
                Paddle(
                    symbol: "plus",
                    accessibilityLabel: "Increase \(chip) budget"
                ) { adjust(+5) }
            }
            Text(caption)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(NG.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ngCard()
        .sensoryFeedback(.selection, trigger: minutes)
    }

    private func Paddle(
        symbol: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .background(tint.opacity(0.13), in: Circle())
                .overlay(Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
