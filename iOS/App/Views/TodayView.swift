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
    static let distractionsMonth = Self("Distractions Month")
    static let messagesMonth = Self("Messages Month")
    static let distractionsMovers = Self("Distractions Movers")
    static let combined = Self("Combined")
}

enum StatsRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "7 Days"
    case month = "30 Days"
    case rhythm = "Rhythm"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .week: return "7 days"
        case .month: return "30 days"
        case .rhythm: return "Rhythm"
        }
    }

    /// How many days of history this range covers. 30 is `HistoryStore.maxDays`
    /// — all the history there is, so no range may claim more.
    var dayCount: Int {
        switch self {
        case .today: return 1
        case .week, .rhythm: return 7
        case .month: return HistoryStore.maxDays
        }
    }

    /// Report context for this range, per ledger.
    func context(distractions: Bool) -> DeviceActivityReport.Context {
        switch self {
        case .today: return distractions ? .distractions : .messages
        case .week: return distractions ? .distractionsWeek : .messagesWeek
        case .month: return distractions ? .distractionsMonth : .messagesMonth
        case .rhythm: return distractions ? .distractionsRhythm : .messagesRhythm
        }
    }
}

/// Exact numbers stay inside the report extension. The host supplies only
/// the selected tokens, range, and targets.
struct TodayView: View {
    @EnvironmentObject private var model: ScreenTimeModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var range: StatsRange = .today
    @State private var now = Date()
    @ScaledMetric(relativeTo: .body) private var reportScale: CGFloat = 1
    let chooseApps: () -> Void
    private let refresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var todayInterval: DateInterval {
        Calendar.current.dateInterval(of: .day, for: now)
            ?? DateInterval(start: now, duration: 3600)
    }

    private var rangeInterval: DateInterval {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -(range.dayCount - 1),
                                  to: todayInterval.start) ?? todayInterval.start
        return DateInterval(start: start, end: todayInterval.end)
    }

    private func filter(apps: Set<ApplicationToken>, webDomains: Set<WebDomainToken>) -> DeviceActivityFilter {
        DeviceActivityFilter(
            segment: range == .rhythm ? .hourly(during: rangeInterval) : .daily(during: rangeInterval),
            users: .all,
            devices: UIDevice.current.userInterfaceIdiom == .pad ? .init([.iPad]) : .init([.iPhone]),
            applications: apps, categories: [], webDomains: webDomains
        )
    }

    private var distractionsActive: Bool {
        !model.activeDistractionApps.isEmpty || !model.activeDistractionWebDomains.isEmpty
    }
    private var messagesActive: Bool { !model.activeMessagesApps.isEmpty }

    private func reportHeight(distractions: Bool) -> CGFloat {
        let base: CGFloat
        switch range {
        case .today:
            if distractions {
                base = 192 + CGFloat(min(4, model.activeDistractionApps.count)) * 29
            } else {
                let count = model.activeMessagesApps.count
                base = count <= 1 ? 140 : 135 + CGFloat(min(4, count)) * 26
            }
        case .week, .month: base = 330
        case .rhythm: base = 210
        }
        return base * max(1, reportScale)
    }

    private var headerDetail: String {
        if range == .today { return now.formatted(.dateTime.weekday(.wide).day().month(.wide)) }
        return "\(rangeInterval.start.formatted(.dateTime.day().month())) – \(now.formatted(.dateTime.day().month()))"
    }

    private var reportRevision: String {
        "\(range.rawValue)-\(DayKey.today(now))-\(model.config.distractionBudget(on: now))-\(model.config.messagesBudgetMinutes)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SignalHeader(title: range.title, detail: headerDetail,
                             badge: UIDevice.current.userInterfaceIdiom == .pad ? "This iPad" : "This iPhone")
                    .padding(.top, 8)
                RangePicker(selection: $range)
                AdaptiveCards {
                    UsageCard(chip: "Distractions", tint: NG.distraction, budgetLabel: budgetLabel,
                              isInstrument: range == .today) {
                        if distractionsActive {
                            DeviceActivityReport(range.context(distractions: true),
                                filter: filter(apps: model.activeDistractionApps,
                                               webDomains: model.activeDistractionWebDomains))
                                .frame(height: reportHeight(distractions: true))
                                .id("distractions-\(reportRevision)")
                        } else {
                            emptyState(model.distractionSelection.isEmpty
                                ? "Choose the apps and sites to count."
                                : "All selected apps are paused or in Messages.",
                                inverted: range == .today)
                        }
                    }
                    UsageCard(chip: "Messages", tint: NG.msg, budgetLabel: budgetLabel) {
                        if messagesActive {
                            DeviceActivityReport(range.context(distractions: false),
                                filter: filter(apps: model.activeMessagesApps, webDomains: []))
                                .frame(height: reportHeight(distractions: false))
                                .id("messages-\(reportRevision)")
                        } else {
                            emptyState(model.messagesSelection.isEmpty
                                ? "Keep messaging apps on a separate total."
                                : "All messaging apps are paused.")
                        }
                    }
                    if range == .month, distractionsActive {
                        UsageCard(chip: "What changed", tint: NG.distraction,
                                  budgetLabel: "7 days vs. prior 23") {
                            DeviceActivityReport(.distractionsMovers,
                                filter: filter(apps: model.activeDistractionApps,
                                               webDomains: model.activeDistractionWebDomains))
                                .frame(height: 190 * max(1, reportScale))
                                .id("movers-\(reportRevision)")
                        }
                    }
                }
            }
            .ngReadingWidth(sizeClass)
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
        .background(NG.paper.ignoresSafeArea())
        .onReceive(refresh) { now = $0 }
        .onAppear { now = .now }
    }

    private var budgetLabel: String {
        switch range {
        case .today: return ""
        case .week, .month: return "\(range.dayCount) days"
        case .rhythm: return "By hour · 7 days"
        }
    }

    private func emptyState(_ message: String, inverted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message).font(.subheadline).foregroundStyle(inverted ? NG.instrumentSoft : NG.inkSoft)
            Button("Choose apps", action: chooseApps)
                .font(.subheadline.weight(.medium)).tint(inverted ? NG.instrumentAccent : NG.distraction)
                .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
    }
}

struct RangePicker: View {
    @Binding var selection: StatsRange

    var body: some View {
        HStack(spacing: 0) {
            ForEach(StatsRange.allCases) { range in
                Button { selection = range } label: {
                    Text(range.rawValue)
                        .font(.ngMono(12)).lineLimit(1).minimumScaleFactor(0.85)
                        .foregroundStyle(selection == range ? NG.ink : NG.inkSoft)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(selection == range ? NG.ink : NG.line)
                                .frame(height: selection == range ? 3 : 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == range ? .isSelected : [])
            }
        }
    }
}

struct UsageCard<Content: View>: View {
    let chip: String
    let tint: Color
    let budgetLabel: String
    var isInstrument: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SignalLabel(title: chip, tint: isInstrument ? NG.instrumentAccent : tint,
                            foreground: isInstrument ? NG.instrumentInk : NG.ink)
                Spacer(minLength: 8)
                if !budgetLabel.isEmpty {
                    Text(budgetLabel).font(.ngMono(10)).foregroundStyle(NG.inkSoft)
                }
            }
            content
        }
        .padding(20)
        .background(isInstrument ? NG.instrument : NG.card,
                    in: RoundedRectangle(cornerRadius: isInstrument ? 5 : 0))
        .overlay(alignment: .top) {
            if !isInstrument { Rectangle().fill(NG.line).frame(height: 1) }
        }
    }
}
