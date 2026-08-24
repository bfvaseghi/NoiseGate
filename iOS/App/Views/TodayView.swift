import SwiftUI
import DeviceActivity
import FamilyControls
import ManagedSettings
import UIKit

extension DeviceActivityReport.Context {
    static let distractions = Self("Distractions")
    static let messages = Self("Messages")
    static let distractionsWeek = Self("Distractions Week")
    static let messagesWeek = Self("Messages Week")
}

enum StatsRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "7 Days"
    var id: String { rawValue }
}

/// Usage overview: exact durations rendered by the report extension
/// (privacy-preserving — the numbers never leave the report view), scoped to
/// only the active Distractions and Messages tokens, for today or the last 7 days.
struct TodayView: View {
    @EnvironmentObject private var model: ScreenTimeModel
    @State private var snapshot = UsageSnapshot.loadToday()
    @State private var range: StatsRange = .today

    private let refresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var todayInterval: DateInterval {
        Calendar.current.dateInterval(of: .day, for: .now)
            ?? DateInterval(start: .now, duration: 3600)
    }

    private var weekInterval: DateInterval {
        let calendar = Calendar.current
        let start = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -6, to: .now) ?? .now
        )
        // A stable day-boundary interval prevents the report extension from
        // re-querying just because SwiftUI evaluated this view a moment later.
        return DateInterval(start: start, end: todayInterval.end)
    }

    private func filter(
        apps: Set<ApplicationToken>,
        webDomains: Set<WebDomainToken>
    ) -> DeviceActivityFilter {
        DeviceActivityFilter(
            segment: .daily(during: range == .today ? todayInterval : weekInterval),
            users: .all,
            devices: UIDevice.current.userInterfaceIdiom == .pad
                ? .init([.iPad]) : .init([.iPhone]),
            applications: apps,
            categories: [],
            webDomains: webDomains
        )
    }

    private var distractionOver: Bool {
        snapshot.distractionMinutes >= snapshot.distractionBudgetMinutes
            && snapshot.distractionBudgetMinutes > 0
    }

    private var distractionsActive: Bool {
        !model.activeDistractionApps.isEmpty || !model.activeDistractionWebDomains.isEmpty
    }
    private var messagesActive: Bool {
        !model.activeMessagesApps.isEmpty
    }

    private var reportHeight: CGFloat { range == .today ? 168 : 214 }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PosterHeader(
                    eyebrow: "NoiseGate",
                    title: range == .today ? "TODAY." : "7 DAYS.",
                    detail: range == .today
                        ? Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
                        : "\(weekInterval.start.formatted(.dateTime.day().month())) – \(Date.now.formatted(.dateTime.day().month()))"
                )
                .padding(.top, 8)

                RangePicker(selection: $range)

                if range == .today && distractionOver {
                    OverBudgetBanner(
                        overMinutes: snapshot.distractionMinutes
                            - snapshot.distractionBudgetMinutes,
                        budgetMinutes: snapshot.distractionBudgetMinutes
                    )
                }

                UsageCard(
                    chip: "Distractions", tint: NG.distraction,
                    budgetLabel: budgetLabel(model.config.distractionBudgetMinutes)
                ) {
                    if !distractionsActive {
                        MissingSelectionRow(text: model.distractionSelection.isEmpty
                            ? "Add distracting apps in the Apps tab."
                            : "All distracting apps are paused or counted in Messages.")
                    } else {
                        DeviceActivityReport(
                            range == .today ? .distractions : .distractionsWeek,
                            filter: filter(
                                apps: model.activeDistractionApps,
                                webDomains: model.activeDistractionWebDomains
                            )
                        )
                        .frame(height: reportHeight)
                        .id("distractions-\(range.rawValue)")
                    }
                }

                UsageCard(
                    chip: "Messages", tint: NG.msg,
                    budgetLabel: budgetLabel(model.config.messagesBudgetMinutes)
                ) {
                    if !messagesActive {
                        MissingSelectionRow(text: model.messagesSelection.isEmpty
                            ? "Add the Messages app in the Apps tab."
                            : "Messages tracking is currently paused.")
                    } else {
                        DeviceActivityReport(
                            range == .today ? .messages : .messagesWeek,
                            filter: filter(
                                apps: model.activeMessagesApps,
                                webDomains: []
                            )
                        )
                        .frame(height: reportHeight)
                        .id("messages-\(range.rawValue)")
                    }
                }

                Text("Only Distractions and Messages are counted. Everything else is excluded as noise. Nothing is blocked.")
                    .font(.ngLabel(11.5))
                    .foregroundStyle(NG.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 96) // room for the floating tab bar
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background(NG.paper.ignoresSafeArea())
        .onAppear { snapshot = UsageSnapshot.loadToday() }
        .onReceive(refresh) { _ in snapshot = UsageSnapshot.loadToday() }
    }

    private func budgetLabel(_ minutes: Int) -> String {
        range == .today
            ? "BUDGET \(minutes.asHoursMinutes)"
            : "BUDGET \(minutes.asHoursMinutes)/DAY"
    }
}

/// Compact capsule switcher between Today and 7 Days, matching the tab bar.
struct RangePicker: View {
    @Binding var selection: StatsRange
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(StatsRange.allCases) { range in
                Button {
                    withAnimation(reduceMotion
                        ? nil : .spring(response: 0.3, dampingFraction: 0.85)) {
                        selection = range
                    }
                } label: {
                    Text(range.rawValue.uppercased())
                        .font(.ngLabel(11))
                        .tracking(1.5)
                        .foregroundStyle(selection == range ? .white : NG.inkSoft)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background {
                            if selection == range {
                                Capsule()
                                    .fill(NG.ink)
                                    .matchedGeometryEffect(id: "rangePill", in: pill)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(NG.card, in: Capsule())
        .overlay(Capsule().strokeBorder(NG.line, lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Card frame around each usage report: category chip + budget in the header,
/// exact numbers (from the report extension) inside.
struct UsageCard<Content: View>: View {
    let chip: String
    let tint: Color
    let budgetLabel: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                NGChip(text: chip, tint: tint)
                Spacer()
                Text(budgetLabel)
                    .font(.ngLabel(10))
                    .tracking(1.5)
                    .foregroundStyle(NG.inkSoft)
            }
            content
        }
        .ngCard()
    }
}

/// Status card shown once the distraction budget is reached. Factual only —
/// nothing is blocked.
struct OverBudgetBanner: View {
    let overMinutes: Int
    let budgetMinutes: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(NG.alarm, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Distraction budget reached")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(NG.ink)
                Text(overMinutes > 0
                        ? "At least \(overMinutes.asHoursMinutes) over today's \(budgetMinutes.asHoursMinutes) budget. Resets at midnight."
                        : "Today's \(budgetMinutes.asHoursMinutes) budget is used. Resets at midnight.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NG.inkSoft)
            }
            Spacer()
        }
        .ngCard(padding: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(NG.alarm.opacity(0.35), lineWidth: 1.5)
        )
    }
}

struct MissingSelectionRow: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "hand.point.up.left")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(NG.inkSoft)
            .padding(.vertical, 8)
    }
}
