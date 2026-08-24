import SwiftUI
import DeviceActivity
import FamilyControls
import ManagedSettings

extension DeviceActivityReport.Context {
    static let noise = Self("Noise")
    static let messages = Self("Messages")
}

/// Today's picture: exact durations rendered by the report extension
/// (privacy-preserving — the numbers never leave the report view), scoped to
/// only the *active* noise and messages tokens. Paused apps and everything
/// you never flagged are invisible here. No everything-feed.
struct TodayView: View {
    @EnvironmentObject private var model: ScreenTimeModel
    @State private var snapshot = UsageSnapshot.loadToday()

    private let refresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var todayInterval: DateInterval {
        Calendar.current.dateInterval(of: .day, for: .now)
            ?? DateInterval(start: .now, duration: 3600)
    }

    private func filter(
        apps: Set<ApplicationToken>,
        categories: Set<ActivityCategoryToken>,
        webDomains: Set<WebDomainToken>
    ) -> DeviceActivityFilter {
        DeviceActivityFilter(
            segment: .daily(during: todayInterval),
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

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                PosterHeader(
                    eyebrow: "NoiseGate",
                    title: "TODAY.",
                    detail: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
                )
                .padding(.top, 8)

                if noiseOver {
                    OverBudgetBanner(
                        overMinutes: snapshot.noiseMinutes - snapshot.noiseBudgetMinutes
                    )
                }

                UsageCard(
                    chip: "Noise", tint: NG.noise,
                    budget: model.config.noiseBudgetMinutes
                ) {
                    if !noiseActive {
                        MissingSelectionRow(text: model.noiseSelection.isEmpty
                            ? "Pick your noise apps in the Noise tab."
                            : "Everything here is paused right now.")
                    } else {
                        DeviceActivityReport(.noise, filter: filter(
                            apps: model.activeNoiseApps,
                            categories: model.activeNoiseCategories,
                            webDomains: model.noiseSelection.webDomainTokens
                        ))
                        .frame(height: 168)
                    }
                }

                UsageCard(
                    chip: "Messages", tint: NG.msg,
                    budget: model.config.messagesBudgetMinutes
                ) {
                    if !messagesActive {
                        MissingSelectionRow(text: model.messagesSelection.isEmpty
                            ? "Add the Messages app in the Noise tab."
                            : "Messages tracking is paused right now.")
                    } else {
                        DeviceActivityReport(.messages, filter: filter(
                            apps: model.activeMessagesApps,
                            categories: model.activeMessagesCategories,
                            webDomains: model.messagesSelection.webDomainTokens
                        ))
                        .frame(height: 168)
                    }
                }

                Text("Only the apps you flagged are counted — nothing here gets blocked, and everything else on this device is none of NoiseGate's business.")
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
}

/// Card frame around each usage report: category chip + budget in the header,
/// exact numbers (from the report extension) inside.
struct UsageCard<Content: View>: View {
    let chip: String
    let tint: Color
    let budget: Int
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                NGChip(text: chip, tint: tint)
                Spacer()
                Text("BUDGET \(budget.asHoursMinutes)")
                    .font(.ngLabel(10))
                    .tracking(1.5)
                    .foregroundStyle(NG.inkSoft)
            }
            content
        }
        .ngCard()
    }
}

/// A calm heads-up once the noise budget is spent. Informative, not scolding —
/// and nothing gets blocked.
struct OverBudgetBanner: View {
    let overMinutes: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(NG.alarm, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Over your line today")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(NG.ink)
                Text(overMinutes > 0
                        ? "At least \(overMinutes.asHoursMinutes) past your noise budget. Tomorrow resets the count."
                        : "You've hit your noise budget. Tomorrow resets the count.")
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
