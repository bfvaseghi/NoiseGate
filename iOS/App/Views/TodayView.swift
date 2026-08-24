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
        NavigationStack {
            List {
                if noiseOver {
                    Section {
                        OverBudgetBanner(
                            overMinutes: snapshot.noiseMinutes - snapshot.noiseBudgetMinutes,
                            blocked: model.config.blockNoiseAtBudget
                        )
                        .listRowInsets(EdgeInsets())
                    }
                }

                Section("Noise") {
                    if model.noiseSelection.isEmpty {
                        MissingSelectionRow(text: "Pick your noise apps in the Blocking tab.")
                    } else {
                        DeviceActivityReport(.noise, filter: filter(for: model.noiseSelection))
                            .frame(height: 170)
                    }
                }
                Section("Messages") {
                    if model.messagesSelection.isEmpty {
                        MissingSelectionRow(text: "Pick your messaging apps in the Blocking tab.")
                    } else {
                        DeviceActivityReport(.messages, filter: filter(for: model.messagesSelection))
                            .frame(height: 170)
                    }
                }
                Section {
                    Label(
                        model.focusOn
                            ? "Focus is ON — noise apps are walled off."
                            : "Focus is off.",
                        systemImage: model.focusOn ? "moon.fill" : "moon"
                    )
                    .font(model.focusOn ? .body.weight(.bold) : .body)
                    .foregroundStyle(model.focusOn ? Color.indigo : .secondary)
                } footer: {
                    Text("Only the apps you flagged are counted. Everything else on this device is none of NoiseGate's business.")
                }
            }
            .navigationTitle("Today")
            .onAppear { snapshot = UsageSnapshot.loadToday() }
            .onReceive(refresh) { _ in snapshot = UsageSnapshot.loadToday() }
        }
    }
}

/// Full-width red slab shown the moment the noise budget is spent.
struct OverBudgetBanner: View {
    let overMinutes: Int
    let blocked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("YOU'RE OVER.", systemImage: "exclamationmark.octagon.fill")
                .font(.system(.title2, design: .rounded).weight(.black))
            Text(blocked
                    ? "Noise budget spent — the wall is up until midnight."
                    : overMinutes > 0
                        ? "At least \(overMinutes.asHoursMinutes) past your noise budget, and nothing is stopping you. That was your call."
                        : "Noise budget spent, and nothing is stopping you. That was your call.")
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(LinearGradient(colors: [.red, .orange],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

struct MissingSelectionRow: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "hand.point.up.left")
            .foregroundStyle(.secondary)
    }
}
