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
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: NGTab = .today

    /// A Shortcut leaves its destination in the app group because it cannot
    /// open a URL for us. Both a cold launch and a resume pick it up here.
    private func consumePendingRoute() {
        guard let route = NoiseGateRoute.consumePending() else { return }
        tab = route.tab
    }

    var body: some View {
        Group {
            if model.isAuthorized {
                VStack(spacing: 0) {
                    Group {
                        switch tab {
                        case .today: TodayView(chooseApps: { tab = .tracking })
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
        .alert("Something went wrong", isPresented: .init(
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
        .onAppear { consumePendingRoute() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            consumePendingRoute()
        }
    }
}

/// The bar occupies its own space so it never covers the final control.
struct NGTabBar: View {
    @Binding var selection: NGTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(NGTab.allCases) { tab in
                Button { selection = tab } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.icon).font(.system(size: 17, weight: .medium))
                        Text(tab.label).font(.caption.weight(.medium))
                    }
                    .foregroundStyle(selection == tab ? NG.ink : NG.inkSoft)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(alignment: .top) {
                        if selection == tab {
                            Rectangle().fill(NG.brand).frame(width: 22, height: 3)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(NG.line).frame(height: 1) }
        .frame(maxWidth: 480)
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var model: ScreenTimeModel
    @State private var requestingAccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                SignalHeader(title: "Keep the signal.")
                Text("Choose what counts.")
                    .font(.title3.weight(.medium)).foregroundStyle(NG.ink)
                VStack(alignment: .leading, spacing: 22) {
                    introduction("Distractions", tint: NG.distraction,
                                 detail: "The apps and sites you want to watch.")
                    introduction("Messages", tint: NG.msg,
                                 detail: "Conversation time, on its own line.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .ngCard()
                Text("Everything else stays untracked.")
                    .font(.subheadline).foregroundStyle(NG.inkSoft)
                Button {
                    requestingAccess = true
                    Task {
                        await model.requestAuthorization()
                        requestingAccess = false
                    }
                } label: {
                    HStack(spacing: 10) {
                        if requestingAccess { ProgressView().tint(NG.onInk) }
                        Text(requestingAccess ? "Requesting access…" : "Connect Screen Time")
                    }
                    .font(.body.weight(.medium)).foregroundStyle(NG.onInk)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(NG.ink, in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .disabled(requestingAccess)
                Text("Access lets NoiseGate measure your choices. It never blocks an app.")
                    .font(.footnote).foregroundStyle(NG.inkSoft)
            }
            .padding(24).padding(.top, 48)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(NG.paper.ignoresSafeArea())
    }

    private func introduction(_ title: String, tint: Color, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SignalLabel(title: title, tint: tint)
            Text(detail).font(.subheadline).foregroundStyle(NG.inkSoft)
        }
    }
}
