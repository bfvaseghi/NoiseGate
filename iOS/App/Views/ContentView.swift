import SwiftUI
import FamilyControls

struct ContentView: View {
    @EnvironmentObject private var model: ScreenTimeModel

    var body: some View {
        Group {
            if model.isAuthorized {
                TabView {
                    TodayView()
                        .tabItem { Label("Today", systemImage: "gauge.with.needle") }
                    BlockingView()
                        .tabItem { Label("Blocking", systemImage: "shield.lefthalf.filled") }
                    SettingsView()
                        .tabItem { Label("Budgets", systemImage: "slider.horizontal.3") }
                }
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
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var model: ScreenTimeModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "waveform.slash")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("NoiseGate")
                .font(.largeTitle.bold())
            Text("""
            Screen Time counts everything — even the apps you're *supposed* to use. \
            NoiseGate only watches the apps you flag as noise, tracks messaging \
            separately, and nudges you when you drift.
            """)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            Spacer()
            Button {
                Task { await model.requestAuthorization() }
            } label: {
                Text("Allow Screen Time access")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            Text("NoiseGate never sees which apps you pick — Apple's Screen Time keeps the list opaque, even to this app.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.bottom)
        }
    }
}
