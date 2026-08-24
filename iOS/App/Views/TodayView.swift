import SwiftUI
import DeviceActivity
import FamilyControls

extension DeviceActivityReport.Context {
    static let noise = Self("Noise")
    static let messages = Self("Messages")
}

/// Today's picture: exact durations rendered by the report extension
/// (privacy-preserving — the numbers never leave the report view), scoped to
/// only the noise selection and the messages selection. No everything-feed.
struct TodayView: View {
    @EnvironmentObject private var model: ScreenTimeModel
    @State private var snapshot = UsageSnapshot.loadToday()

    private let refresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var todayInterval: DateInterval {
        Calendar.current.dateInterval(of: .day, for: .now)
            ?? DateInterval(start: .now, duration: 3600)
    }

    private func filter(for selection: FamilyActivitySelection) -> DeviceActivityFilter {
        DeviceActivityFilter(
            segment: .daily(during: todayInterval),
            users: .all,
            devices: .init([.iPhone, .iPad]),
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens
        )
    }

    private var noiseOver: Bool {
        snapshot.noiseMinutes >= snapshot.noiseBudgetMinutes && snapshot.noiseBudgetMinutes > 0
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
                        overMinutes: snapshot.noiseMinutes - snapshot.noiseBudgetMinutes,
                        blocked: model.config.blockNoiseAtBudget
                    )
                }

                UsageCard(
                    chip: "Noise", tint: NG.noise,
                    budget: model.config.noiseBudgetMinutes
                ) {
                    if model.noiseSelection.isEmpty {
                        MissingSelectionRow(text: "Pick your noise apps in the Blocking tab.")
                    } else {
                        DeviceActivityReport(.noise, filter: filter(for: model.noiseSelection))
                            .frame(height: 168)
                    }
                }

                UsageCard(
                    chip: "Messages", tint: NG.msg,
                    budget: model.config.messagesBudgetMinutes
                ) {
                    if model.messagesSelection.isEmpty {
                        MissingSelectionRow(text: "Pick your messaging apps in the Blocking tab.")
                    } else {
                        DeviceActivityReport(.messages, filter: filter(for: model.messagesSelection))
                            .frame(height: 168)
                    }
                }

                FocusStatusCard(focusOn: model.focusOn)

                Text("Only the apps you flagged are counted. Everything else on this device is none of NoiseGate's business.")
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

/// Full-width alarm slab with hazard stripes, shown the moment the noise
/// budget is spent.
struct OverBudgetBanner: View {
    let overMinutes: Int
    let blocked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOU'RE OVER.")
                .font(.ngDisplay(34))
            Text(blocked
                    ? "Noise budget spent — the wall is up until midnight."
                    : overMinutes > 0
                        ? "At least \(overMinutes.asHoursMinutes) past your noise budget, and nothing is stopping you. That was your call."
                        : "Noise budget spent, and nothing is stopping you. That was your call.")
                .font(.system(size: 14.5, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            ZStack {
                NG.overBannerGradient
                HazardStripes(opacity: 0.10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        )
        .shadow(color: NG.alarm.opacity(0.35), radius: 18, y: 8)
    }
}

struct FocusStatusCard: View {
    let focusOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: focusOn ? "moon.fill" : "moon")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(focusOn ? Color.white : NG.inkSoft)
                .frame(width: 40, height: 40)
                .background(
                    focusOn ? AnyShapeStyle(NG.focusGradient) : AnyShapeStyle(NG.line.opacity(0.5)),
                    in: Circle()
                )
            Text(focusOn ? "Focus is ON — noise apps are walled off." : "Focus is off.")
                .font(.system(size: 15, weight: focusOn ? .bold : .medium))
                .foregroundStyle(focusOn ? NG.ink : NG.inkSoft)
            Spacer()
        }
        .ngCard(padding: 14)
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
