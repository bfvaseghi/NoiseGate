import SwiftUI

/// Menu-bar-only companion. macOS has no public Screen Time API for third
/// parties, so this app does its own honest accounting: it samples the
/// frontmost app a few times a minute, counts only the apps you've flagged,
/// and enforces blocks by hiding noise apps (best effort — see README).
@main
struct NoiseGateMacApp: App {
    @StateObject private var model = MacModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(model)
        } label: {
            // Over budget? Say so right in the menu bar.
            if model.noiseMinutesToday >= model.config.noiseBudgetMinutes {
                Label("OVER", systemImage: "exclamationmark.octagon.fill")
                    .labelStyle(.titleAndIcon)
            } else {
                Image(systemName: model.enforcementActive ? "moon.fill" : "waveform.slash")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            MacSettingsView()
                .environmentObject(model)
        }
    }
}
