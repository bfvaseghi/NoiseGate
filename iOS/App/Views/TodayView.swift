import SwiftUI
import DeviceActivity
import FamilyControls
import ManagedSettings

extension DeviceActivityReport.Context {
    static let noise = Self("Noise")
    static let messages = Self("Messages")
    static let noiseWeek = Self("Noise Week")
    static let messagesWeek = Self("Messages Week")
}

enum StatsRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "7 Days"
    var id: String { rawValue }
}

/// Usage overview: exact durations rendered by the report extension
/// (privacy-preserving — the numbers never leave the report view), scoped to
/// only the *active* noise and messages tokens, for today or the last 7 days.
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
        return DateInterval(start: start, end: .now)
    }

    private func filter(
        apps: Set<ApplicationToken>,
        categories: Set<ActivityCategoryToken>,
        webDomains: Set<WebDomainToken>
    ) -> DeviceActivityFilter {
        DeviceActivityFilter(
            segment: .daily(during: range == .today ? todayInterval : weekInterval),
            users: .all,
            devices: .init([.iPhone, .iPad]),
            applications: apps,
            categories: categories,
            webDomains: webDomains
        )
    }

    private var noiseOver: Bool {
        snapshot.noiseMinutes >= snapshot.noiseBudgetMinutes && snapshot.noiseBudgetMinutes > 0
    }

    private var noiseActive: Bool {
        !model.activeNoiseApps.isEmpty || !model.activeNoiseCategories.isEmpty
    }
    private var messagesActive: Bool {
        !model.activeMessagesApps.isEmpty || !model.activeMessagesCategories.isEmpty
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

                if range == .today && noiseOver {
                    OverBudgetBanner(
                        overMinutes: snapshot.noiseMinutes - snapshot.noiseBudgetMinutes,
                        budgetMinutes: snapshot.noiseBudgetMinutes
                    )
                }

                UsageCard(
                    chip: "Noise", tint: NG.noise,
                    budgetLabel: budgetLabel(model.config.noiseBudgetMinutes)
                ) {
                    if !noiseActive {
                        MissingSelectionRow(text: model.noiseSelection.isEmpty
                            ? "Add noise apps in the Noise tab."
                            : "All noise apps are currently paused.")
                    } else {
                        DeviceActivityReport(
                            range == .today ? .noise : .noiseWeek,
                            filter: filter(
                                apps: model.activeNoiseApps,
                                categories: model.activeNoiseCategories,
                                webDomains: model.noiseSelection.webDomainTokens
                            )
                        )
                        .frame(height: reportHeight)
                        .id("noise-\(range.rawValue)")
                    }
                }

                UsageCard(
                    chip: "Messages", tint: NG.msg,
                    budgetLabel: budgetLabel(model.config.messagesBudgetMinutes)
                ) {
                    if !messagesActive {
                        MissingSelectionRow(text: model.messagesSelection.isEmpty
                            ? "Add the Messages app in the Noise tab."
                            : "Messages tracking is currently paused.")
                    } else {
                        DeviceActivityReport(
                            range == .today ? .messages : .messagesWeek,
                            filter: filter(
                                apps: model.activeMessagesApps,
                                categories: model.activeMessagesCategories,
                                webDomains: model.messagesSelection.webDomainTokens
                            )
                        )
                        .frame(height: reportHeight)
                        .id("messages-\(range.rawValue)")
                    }
                }

                HistoryStatsCard(todaySnapshot: snapshot)

                Text("Only listed apps are counted. Nothing is blocked.")
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
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(StatsRange.allCases) { range in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
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

/// Status card shown once the noise budget is reached. Factual only —
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
                Text("Noise budget reached")
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

/// "Budget reached on N of the last M days" — from the rollover history plus
/// today's snapshot. Values are threshold floors on iOS, marked accordingly.
struct HistoryStatsCard: View {
    let todaySnapshot: UsageSnapshot

    private var records: [DayRecord] {
        var records = HistoryStore.lastDays(6)
        records.append(DayRecord(
            dayKey: todaySnapshot.dayKey,
            noiseMinutes: todaySnapshot.noiseMinutes,
            messagesMinutes: todaySnapshot.messagesMinutes,
            noiseBudgetMinutes: todaySnapshot.noiseBudgetMinutes,
            messagesBudgetMinutes: todaySnapshot.messagesBudgetMinutes,
            isFloor: true
        ))
        return records
    }

    var body: some View {
        let records = self.records
        // One day of data isn't a trend yet.
        if records.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                Text("LAST \(records.count) DAYS")
                    .font(.ngLabel(10))
                    .tracking(2)
                    .foregroundStyle(NG.inkSoft)
                statRow(
                    tint: NG.noise,
                    label: "Noise budget reached",
                    count: records.filter(\.noiseReachedBudget).count,
                    total: records.count
                )
                statRow(
                    tint: NG.msg,
                    label: "Messages budget reached",
                    count: records.filter(\.messagesReachedBudget).count,
                    total: records.count
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .ngCard(padding: 16)
        }
    }

    private func statRow(tint: Color, label: String, count: Int, total: Int) -> some View {
        HStack {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NG.ink)
            Spacer()
            Text("\(count) of \(total) days")
                .font(.ngNumber(14))
                .foregroundStyle(count > 0 ? NG.ink : NG.inkSoft)
        }
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
