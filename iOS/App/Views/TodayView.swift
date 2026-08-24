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
    static let distractionsRhythm = Self("Distractions Rhythm")
    static let messagesRhythm = Self("Messages Rhythm")
    static let combined = Self("Combined")
}

enum StatsRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "7 Days"
    case rhythm = "Rhythm"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "TODAY."
        case .week: return "7 DAYS."
        case .rhythm: return "RHYTHM."
        }
    }

    /// Report context for this range, per ledger.
    func context(distractions: Bool) -> DeviceActivityReport.Context {
        switch self {
        case .today: return distractions ? .distractions : .messages
        case .week: return distractions ? .distractionsWeek : .messagesWeek
        case .rhythm: return distractions ? .distractionsRhythm : .messagesRhythm
        }
    }
}

/// Usage overview: exact durations rendered by the report extension
/// (privacy-preserving — the numbers never leave the report view), scoped to
/// only the active Distractions and Messages tokens, for today or the last 7 days.
struct TodayView: View {
    @EnvironmentObject private var model: ScreenTimeModel
    @State private var snapshot = UsageSnapshot.loadToday()
    @State private var history: [DayRecord] = HistoryStore.lastDays(30)
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
        // Rhythm needs hour-of-day resolution; the other ranges only need
        // daily totals, which is far cheaper for Screen Time to compute.
        let segment: DeviceActivityFilter.SegmentInterval = range == .rhythm
            ? .hourly(during: weekInterval)
            : .daily(during: range == .today ? todayInterval : weekInterval)
        return DeviceActivityFilter(
            segment: segment,
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

    private var reportHeight: CGFloat {
        switch range {
        // Today now carries a ring, the pickup stats, and up to four app rows.
        case .today: return 216
        // 7 Days carries the chart plus the per-app ranking.
        case .week: return 296
        case .rhythm: return 186
        }
    }

    private var headerDetail: String {
        let span = "\(weekInterval.start.formatted(.dateTime.day().month())) – \(Date.now.formatted(.dateTime.day().month()))"
        switch range {
        case .today: return Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
        case .week: return span
        case .rhythm: return "Hour of day · \(span)"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PosterHeader(
                    eyebrow: "NoiseGate",
                    title: range.title,
                    detail: headerDetail
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

                if range == .today, distractionsActive || messagesActive {
                    CombinedCard(
                        budgetMinutes: model.config.distractionBudgetMinutes
                            + model.config.messagesBudgetMinutes
                    ) {
                        DeviceActivityReport(
                            .combined,
                            filter: filter(
                                // The union of both selections: one number for
                                // everything being tracked. The cards below
                                // still show each total on its own.
                                apps: model.activeDistractionApps
                                    .union(model.activeMessagesApps),
                                webDomains: model.activeDistractionWebDomains
                            )
                        )
                        .frame(height: 74)
                        .id("combined")
                    }
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
                            range.context(distractions: true),
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
                            range.context(distractions: false),
                            filter: filter(
                                apps: model.activeMessagesApps,
                                webDomains: []
                            )
                        )
                        .frame(height: reportHeight)
                        .id("messages-\(range.rawValue)")
                    }
                }

                if range == .today {
                    StreakCard(records: history, snapshot: snapshot)
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
        .onAppear {
            snapshot = UsageSnapshot.loadToday()
            history = HistoryStore.lastDays(30)
        }
        .onReceive(refresh) { _ in
            snapshot = UsageSnapshot.loadToday()
            history = HistoryStore.lastDays(30)
        }
    }

    private func budgetLabel(_ minutes: Int) -> String {
        switch range {
        case .today: return "BUDGET \(minutes.asHoursMinutes)"
        case .week: return "BUDGET \(minutes.asHoursMinutes)/DAY"
        case .rhythm: return "AVG PER DAY"
        }
    }
}

/// Compact capsule switcher across the three views, matching the tab bar.
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
                        .foregroundStyle(selection == range ? NG.paper : NG.inkSoft)
                        .frame(maxWidth: .infinity)
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

/// Everything tracked, as one figure. Deliberately quieter than the two
/// ledger cards beneath it: it is the summary, not the detail.
struct CombinedCard<Content: View>: View {
    let budgetMinutes: Int
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ALL TRACKED TIME")
                    .font(.ngLabel(10))
                    .tracking(2)
                    .foregroundStyle(NG.inkSoft)
                Spacer()
                Text("BUDGET \(budgetMinutes.asHoursMinutes)")
                    .font(.ngLabel(10))
                    .tracking(1.5)
                    .foregroundStyle(NG.inkSoft)
            }
            content
        }
        .ngCard(padding: 18)
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

/// Distraction trend over finished days: how many stayed under budget, the
/// current run, the daily average, and the change against the prior week.
/// Numbers only — no praise, no scolding.
struct StreakCard: View {
    let records: [DayRecord]
    let snapshot: UsageSnapshot

    private var stats: StreakStats.Summary {
        StreakStats.distractions(records: records, snapshot: snapshot)
    }

    var body: some View {
        let stats = self.stats
        // One finished day is not yet a pattern; the trend pill has its own,
        // stricter threshold inside `StreakStats`.
        if stats.totalDays >= 2 {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("DISTRACTIONS · LAST \(stats.totalDays) DAYS")
                        .font(.ngLabel(10))
                        .tracking(2)
                        .foregroundStyle(NG.inkSoft)
                    Spacer()
                    if let trend = stats.trendPercent, trend != 0 {
                        TrendPill(percent: trend)
                    }
                }
                HStack(alignment: .top, spacing: 0) {
                    StatColumn(
                        value: "\(stats.underBudgetDays)/\(stats.totalDays)",
                        label: "UNDER BUDGET"
                    )
                    Divider().frame(height: 34)
                    StatColumn(
                        value: stats.underBudgetRun == 0 ? "—" : "\(stats.underBudgetRun)",
                        label: stats.underBudgetRun == 1 ? "DAY RUNNING" : "DAYS RUNNING"
                    )
                    Divider().frame(height: 34)
                    StatColumn(
                        value: stats.averageMinutes.asHoursMinutes,
                        label: "DAILY AVERAGE"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .ngCard(padding: 16)
        }
    }
}

private struct StatColumn: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.ngNumber(21))
                .foregroundStyle(NG.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.ngLabel(10))
                .tracking(1.2)
                .foregroundStyle(NG.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Signed change vs. the prior week. Down is drawn calm, up is drawn warm —
/// no value judgment in the words, only in the arrow.
private struct TrendPill: View {
    let percent: Int

    private var isDown: Bool { percent < 0 }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isDown ? "arrow.down.right" : "arrow.up.right")
                .font(.system(size: 9, weight: .black))
            Text("\(abs(percent))%")
                .font(.ngLabel(10))
                .tracking(0.5)
        }
        .foregroundStyle(isDown ? NG.msg : NG.distraction)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background((isDown ? NG.msg : NG.distraction).opacity(0.14), in: Capsule())
        .accessibilityLabel(
            isDown ? "Down \(abs(percent)) percent vs. prior week"
                   : "Up \(percent) percent vs. prior week"
        )
    }
}
