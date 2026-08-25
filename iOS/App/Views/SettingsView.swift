import SwiftUI
import UserNotifications
import WidgetKit

struct SettingsView: View {
    @EnvironmentObject private var model: ScreenTimeModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var accent = AccentTheme.current

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PosterHeader(
                    eyebrow: "Daily budgets",
                    title: "BUDGETS.",
                    detail: "Distractions and Messages each get their own daily target."
                )
                .padding(.top, 8)

                BudgetDial(
                    chip: "Distractions", tint: NG.distraction,
                    minutes: model.config.distractionBudgetMinutes,
                    caption: "Daily target for the distracting apps and sites you chose."
                ) { model.adjustBudget(\.distractionBudgetMinutes, by: $0) }

                WeekendBudgetCard(
                    enabled: model.config.weekendBudgetsEnabled,
                    weekdayMinutes: model.config.distractionBudgetMinutes,
                    weekendMinutes: model.config.weekendDistractionBudgetMinutes,
                    setEnabled: { model.setWeekendBudgets($0) },
                    adjust: { model.adjustBudget(\.weekendDistractionBudgetMinutes, by: $0) }
                )

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
                            Text("Each enabled notification is sent at most once per day, per category. Nothing is blocked.")
                        }
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(NG.inkSoft)
                }
                .ngCard(padding: 16)

                AccentPicker(selection: $accent)

                HistoryExportCard()

                Spacer(minLength: 96)
            }
            .ngReadingWidth(sizeClass)
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

    /// Common targets, so a large change is one tap instead of dozens.
    private static let presets = [15, 30, 45, 60, 90, 120]

    /// Live value while a drag is in flight. The committed budget only changes
    /// on release, so a drag never triggers a write-and-reschedule per pixel.
    @State private var dragMinutes: Int?

    private var shownMinutes: Int { dragMinutes ?? minutes }

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
                    Text(shownMinutes.asHoursMinutes)
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

            // Drag anywhere on the track for coarse changes; the paddles above
            // stay for fine 5-minute steps and for VoiceOver/Switch Control.
            BudgetTrack(
                minutes: shownMinutes,
                tint: tint,
                onDrag: { dragMinutes = $0 },
                onCommit: { target in
                    dragMinutes = nil
                    if target != minutes { adjust(target - minutes) }
                }
            )
            .accessibilityHidden(true)

            HStack(spacing: 6) {
                ForEach(Self.presets, id: \.self) { preset in
                    Button {
                        adjust(preset - minutes)
                    } label: {
                        Text(preset.asHoursMinutes)
                            .font(.ngLabel(10.5))
                            .tracking(0.6)
                            .foregroundStyle(minutes == preset ? .white : NG.inkSoft)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                minutes == preset ? tint : NG.line.opacity(0.55),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Set \(chip) budget to \(preset.asHoursMinutes)")
                }
            }

            Text(caption)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(NG.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ngCard()
        .sensoryFeedback(.selection, trigger: shownMinutes)
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(minutes.asHoursMinutes) per day")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(5)
            case .decrement: adjust(-5)
            @unknown default: break
            }
        }
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

/// Draggable budget track spanning 5 minutes to 8 hours. Uses a square-root
/// scale so the common 15m–2h range gets most of the travel instead of being
/// squeezed into the first eighth of a linear track.
struct BudgetTrack: View {
    let minutes: Int
    let tint: Color
    /// Fires continuously during a drag for live display only.
    let onDrag: (Int) -> Void
    /// Fires once on release; the only path that persists a new budget.
    let onCommit: (Int) -> Void

    private static let minMinutes = 5.0
    private static let maxMinutes = 480.0

    private static func position(for minutes: Double) -> Double {
        let clamped = min(maxMinutes, max(minMinutes, minutes))
        return ((clamped - minMinutes) / (maxMinutes - minMinutes)).squareRoot()
    }

    private static func minutes(atPosition position: Double) -> Int {
        let clamped = min(1, max(0, position))
        let raw = minMinutes + clamped * clamped * (maxMinutes - minMinutes)
        // Snap to the same 5-minute grid the paddles use.
        return Int((raw / 5).rounded()) * 5
    }

    var body: some View {
        GeometryReader { geo in
            let fraction = Self.position(for: Double(minutes))
            let knobX = geo.size.width * fraction
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(NG.line.opacity(0.7))
                    .frame(height: 8)
                Capsule()
                    .fill(tint)
                    .frame(width: max(8, knobX), height: 8)
                Circle()
                    .fill(NG.card)
                    .overlay(Circle().strokeBorder(tint, lineWidth: 3))
                    .frame(width: 22, height: 22)
                    .shadow(color: NG.ink.opacity(0.16), radius: 4, y: 2)
                    .offset(x: max(0, min(geo.size.width - 22, knobX - 11)))
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard geo.size.width > 0 else { return }
                        let target = Self.minutes(
                            atPosition: value.location.x / geo.size.width
                        )
                        if target != minutes { onDrag(target) }
                    }
                    .onEnded { value in
                        guard geo.size.width > 0 else { return }
                        onCommit(Self.minutes(atPosition: value.location.x / geo.size.width))
                    }
            )
        }
        .frame(height: 22)
    }
}

/// Accent selector for the Distractions ledger. Writing the choice reloads
/// widget timelines so the Home Screen picks up the new colour immediately.
/// A separate Saturday and Sunday target for Distractions. Every chart
/// compares a day against the budget that applied on that day, so turning
/// this on never rewrites how last week was judged.
struct WeekendBudgetCard: View {
    let enabled: Bool
    let weekdayMinutes: Int
    let weekendMinutes: Int
    let setEnabled: (Bool) -> Void
    let adjust: (Int) -> Void

    /// Live value while a drag is in flight, matching `BudgetDial`: the
    /// committed budget only moves on release.
    @State private var dragMinutes: Int?

    private var shownMinutes: Int { dragMinutes ?? weekendMinutes }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NGChip(text: "Weekends", tint: NG.distraction)

            Toggle(isOn: Binding(get: { enabled }, set: setEnabled)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saturday and Sunday differ")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(NG.ink)
                    Text(enabled
                            ? "\(weekendMinutes.asHoursMinutes) at weekends, \(weekdayMinutes.asHoursMinutes) on weekdays"
                            : "\(weekdayMinutes.asHoursMinutes) every day")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(NG.inkSoft)
                }
            }
            .tint(NG.distraction)

            if enabled {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(shownMinutes.asHoursMinutes)
                        .font(.ngNumber(30))
                        .foregroundStyle(NG.ink)
                        .contentTransition(.numericText())
                    Text("PER WEEKEND DAY")
                        .font(.ngLabel(10))
                        .tracking(2)
                        .foregroundStyle(NG.inkSoft)
                }

                BudgetTrack(
                    minutes: shownMinutes,
                    tint: NG.distraction,
                    onDrag: { dragMinutes = $0 },
                    onCommit: { target in
                        dragMinutes = nil
                        if target != weekendMinutes { adjust(target - weekendMinutes) }
                    }
                )
                .accessibilityHidden(true)
            }

            Text("Every chart compares a day against the budget that applied on that day, so past days keep their own target. Messages keeps one number.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(NG.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ngCard()
        .sensoryFeedback(.selection, trigger: shownMinutes)
        .accessibilityElement(children: .contain)
        .accessibilityValue(enabled
            ? "\(weekendMinutes.asHoursMinutes) per weekend day"
            : "Off")
        .accessibilityAdjustableAction { direction in
            guard enabled else { return }
            switch direction {
            case .increment: adjust(5)
            case .decrement: adjust(-5)
            @unknown default: break
            }
        }
    }
}

struct AccentPicker: View {
    @Binding var selection: AccentTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        selection.color,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                Text("Accent")
                    .font(.system(size: 15.5, weight: .bold))
                    .foregroundStyle(NG.ink)
                Spacer()
                Text(selection.displayName.uppercased())
                    .font(.ngLabel(10))
                    .tracking(1.5)
                    .foregroundStyle(NG.inkSoft)
            }
            HStack(spacing: 10) {
                ForEach(AccentTheme.allCases) { theme in
                    Button {
                        selection = theme
                        AccentTheme.select(theme)
                        WidgetCenter.shared.reloadAllTimelines()
                    } label: {
                        Circle()
                            .fill(theme.color)
                            .frame(width: 34, height: 34)
                            .overlay {
                                if theme == selection {
                                    Circle()
                                        .strokeBorder(NG.card, lineWidth: 3)
                                        .padding(2)
                                }
                            }
                            .overlay {
                                Circle().strokeBorder(
                                    theme == selection ? NG.ink : NG.line,
                                    lineWidth: theme == selection ? 2 : 1
                                )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.displayName)
                    .accessibilityAddTraits(theme == selection ? [.isSelected] : [])
                }
                Spacer()
            }
            Text("Colours Distractions everywhere, including widgets. Messages keeps its own colour.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(NG.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ngCard(padding: 16)
    }
}
