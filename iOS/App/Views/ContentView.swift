import SwiftUI
import FamilyControls

// MARK: - Root: custom tab shell over the three screens

enum NGTab: String, CaseIterable, Identifiable, Equatable {
    case today, tracking, budgets
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Today"
        case .tracking: return "Apps"
        case .budgets: return "Budgets"
        }
    }

    var icon: String {
        switch self {
        case .today: return "gauge.with.needle"
        case .tracking: return "checklist.checked"
        case .budgets: return "slider.horizontal.3"
        }
    }
}

extension NoiseGateRoute {
    var tab: NGTab {
        switch self {
        case .today: return .today
        case .apps: return .tracking
        case .budgets: return .budgets
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: ScreenTimeModel
    @State private var tab: NGTab = .today

    var body: some View {
        Group {
            if model.isAuthorized {
                ZStack(alignment: .bottom) {
                    Group {
                        switch tab {
                        case .today: TodayView()
                        case .tracking: NoiseView()
                        case .budgets: SettingsView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    NGTabBar(selection: $tab)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                }
                .background(NG.paper.ignoresSafeArea())
                .sensoryFeedback(.selection, trigger: tab)
            } else {
                OnboardingView()
            }
        }
        .alert("NoiseGate needs attention", isPresented: .init(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
        .onOpenURL { url in
            guard let route = NoiseGateRoute(url: url) else { return }
            tab = route.tab
        }
    }
}

/// Floating capsule tab bar with a sliding alarm-red pill.
struct NGTabBar: View {
    @Binding var selection: NGTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(NGTab.allCases) { tab in
                Button {
                    withAnimation(reduceMotion
                        ? nil : .spring(response: 0.32, dampingFraction: 0.82)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .bold))
                        Text(tab.label.uppercased())
                            .font(.ngLabel(9))
                            .tracking(1.2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(selection == tab ? .white : NG.inkSoft)
                    .background {
                        if selection == tab {
                            Capsule()
                                .fill(NG.alarm)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(NG.line, lineWidth: 1))
        .shadow(color: NG.ink.opacity(0.12), radius: 18, y: 8)
        .frame(maxWidth: 420)
    }
}

// MARK: - Onboarding: the poster

struct OnboardingView: View {
    @EnvironmentObject private var model: ScreenTimeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            Image(systemName: "waveform.slash")
                .font(.system(size: 40, weight: .black))
                .foregroundStyle(NG.alarm)
                .padding(.bottom, 28)
                .symbolEffect(
                    .pulse,
                    options: .repeating,
                    isActive: revealed && !reduceMotion
                )

            VStack(alignment: .leading, spacing: -6) {
                PosterLine("KEEP")
                PosterLine("THE")
                PosterLine("SIGNAL", accent: true)
            }
            .padding(.bottom, 24)

            Text("Apple Screen Time mixes distractions with useful activity. NoiseGate removes that noise. It tracks only the distracting apps you choose, plus Messages on a separate line. Everything else stays invisible.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(NG.inkSoft)
                .frame(maxWidth: 340, alignment: .leading)

            Spacer()

            Button {
                Task { await model.requestAuthorization() }
            } label: {
                Text("Allow Screen Time access")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(NG.alarmGradient, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 14)

            Text("Apple keeps token identities opaque. NoiseGate can display Apple's private labels, but it cannot inspect or export the underlying app IDs.")
                .font(.ngLabel(11))
                .foregroundStyle(NG.inkSoft.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
        }
        .padding(28)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NG.paper.ignoresSafeArea())
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.85).delay(0.1)) {
                revealed = true
            }
        }
    }

    private func PosterLine(_ text: String, accent: Bool = false) -> some View {
        (Text(text).foregroundColor(accent ? NG.alarm : NG.ink)
            + Text(".").foregroundColor(accent ? NG.ink : NG.alarm))
            .font(.ngDisplay(84))
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 14)
    }
}
