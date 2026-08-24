import SwiftUI
import DeviceActivity
import FamilyControls

extension DeviceActivityReport.Context {
    static let totalActivity = Self("Total Activity")
}

/// Today's picture: exact durations rendered by the report extension
/// (privacy-preserving — the numbers never leave the report view), scoped to
/// only the noise selection and the messages selection. No everything-feed.
struct TodayView: View {
    @EnvironmentObject private var model: ScreenTimeModel

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

    var body: some View {
        NavigationStack {
            List {
                Section("Noise · \(model.config.noiseBudgetMinutes.asHoursMinutes) budget") {
                    if model.noiseSelection.isEmpty {
                        MissingSelectionRow(text: "Pick your noise apps in the Blocking tab.")
                    } else {
                        DeviceActivityReport(.totalActivity, filter: filter(for: model.noiseSelection))
                            .frame(height: 140)
                    }
                }
                Section("Messages · \(model.config.messagesBudgetMinutes.asHoursMinutes) budget") {
                    if model.messagesSelection.isEmpty {
                        MissingSelectionRow(text: "Pick your messaging apps in the Blocking tab.")
                    } else {
                        DeviceActivityReport(.totalActivity, filter: filter(for: model.messagesSelection))
                            .frame(height: 140)
                    }
                }
                Section {
                    Label(
                        model.focusOn
                            ? "Focus is on — noise apps are blocked."
                            : "Focus is off.",
                        systemImage: model.focusOn ? "moon.fill" : "moon"
                    )
                    .foregroundStyle(model.focusOn ? Color.indigo : .secondary)
                } footer: {
                    Text("Only the apps you flagged are counted. Everything else on your phone is none of NoiseGate's business.")
                }
            }
            .navigationTitle("Today")
        }
    }
}

struct MissingSelectionRow: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "hand.point.up.left")
            .foregroundStyle(.secondary)
    }
}
