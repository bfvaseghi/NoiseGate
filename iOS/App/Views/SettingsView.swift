import SwiftUI
import UserNotifications
import WidgetKit
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var model: ScreenTimeModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var accent = AccentTheme.current

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SignalHeader(title: "Budgets").padding(.top, 8)
                VStack(alignment: .leading, spacing: 16) {
                    BudgetDial(chip: "Distractions", tint: NG.distraction,
                               minutes: model.config.distractionBudgetMinutes,
                               period: model.config.weekendBudgetsEnabled ? "Weekdays" : "Per day") {
                        model.adjustBudget(\.distractionBudgetMinutes, by: $0)
                    }
                    Divider()
                    Toggle("Different weekend target", isOn: Binding(
                        get: { model.config.weekendBudgetsEnabled }, set: model.setWeekendBudgets
                    ))
                    .font(.subheadline).tint(NG.distraction)
                    if model.config.weekendBudgetsEnabled {
                        BudgetDial(chip: "Weekends", tint: NG.distraction,
                                   minutes: model.config.weekendDistractionBudgetMinutes) {
                            model.adjustBudget(\.weekendDistractionBudgetMinutes, by: $0)
                        }
                    }
                }
                .ngCard(padding: 17)
                BudgetDial(chip: "Messages", tint: NG.msg, minutes: model.config.messagesBudgetMinutes) {
                    model.adjustBudget(\.messagesBudgetMinutes, by: $0)
                }
                .ngCard(padding: 17)
                notificationControls
                AccentPicker(selection: $accent)
                HistoryExportCard()
            }
            .foregroundStyle(NG.ink)
            .ngReadingWidth(sizeClass)
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
        .background(NG.paper.ignoresSafeArea())
    }

    private var notificationControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Notifications", isOn: Binding(
                get: { model.config.notificationsEnabled }, set: model.setNotificationsEnabled
            ))
            .font(.subheadline.weight(.medium)).tint(NG.distraction)
            if model.config.notificationsEnabled {
                ForEach(BudgetConfig.nudgePercents, id: \.self) { percent in
                    Toggle("At \(percent)% of target", isOn: Binding(
                        get: { model.config.notifyAt.contains(percent) },
                        set: { model.setNotification(at: percent, enabled: $0) }
                    ))
                    .font(.subheadline).tint(NG.distraction)
                }
                Toggle("Past target · 150% and 200%", isOn: Binding(
                    get: { model.config.overtimeNotifications }, set: model.setOvertimeNotifications
                ))
                .font(.subheadline).tint(NG.distraction)
            }
            if model.notificationStatus == .denied {
                Button("Enable in iPhone Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .font(.subheadline).tint(NG.distraction).frame(minHeight: 44)
            }
        }
        .ngCard(padding: 17)
    }
}

/// One time readout and a native stepper. Presets stay inside a small menu.
struct BudgetDial: View {
    let chip: String
    let tint: Color
    let minutes: Int
    var period: String = "Per day"
    let adjust: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SignalLabel(title: chip, tint: tint)
            HStack(alignment: .center, spacing: 12) {
                Menu {
                    ForEach([15, 30, 45, 60, 90, 120], id: \.self) { value in
                        Button(value.asHoursMinutes) { adjust(value - minutes) }
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(minutes.asHoursMinutes).font(.ngNumber(32)).monospacedDigit()
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .foregroundStyle(NG.ink).frame(minHeight: 44)
                }
                .accessibilityLabel("\(chip) target, \(minutes.asHoursMinutes). Quick choices")
                Spacer(minLength: 0)
                Stepper("\(chip) target", value: Binding(
                    get: { minutes }, set: { adjust($0 - minutes) }
                ), in: 5...480, step: 5)
                .labelsHidden().fixedSize()
                .accessibilityValue("\(minutes.asHoursMinutes) per day")
            }
            Text(period).font(.caption).foregroundStyle(NG.inkSoft)
        }
    }
}

struct AccentPicker: View {
    @Binding var selection: AccentTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Distractions color").font(.subheadline.weight(.medium))
                Spacer()
                Text(selection.displayName).font(.caption).foregroundStyle(NG.inkSoft)
            }
            HStack(spacing: 8) {
                ForEach(AccentTheme.allCases) { theme in
                    Button {
                        selection = theme
                        AccentTheme.select(theme)
                        WidgetCenter.shared.reloadAllTimelines()
                    } label: {
                        Circle().fill(theme.color).frame(width: 28, height: 28)
                            .overlay {
                                if theme == selection {
                                    Circle().strokeBorder(NG.card, lineWidth: 2).padding(3)
                                }
                            }
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.displayName)
                    .accessibilityAddTraits(theme == selection ? .isSelected : [])
                }
            }
        }
        .ngCard(padding: 17)
    }
}
