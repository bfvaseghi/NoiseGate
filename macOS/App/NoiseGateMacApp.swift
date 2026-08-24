import SwiftUI

/// Menu-bar-only companion. macOS has no public Screen Time API for third
/// parties, so this app does its own honest accounting: it samples the
/// frontmost app a few times a minute and counts only the apps you've
/// flagged. Pure awareness — it never blocks or hides anything.
@main
struct NoiseGateMacApp: App {
    @StateObject private var model = MacModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(model)
        } label: {
            Image(systemName: "waveform.slash")
        }
        .menuBarExtraStyle(.window)

        Settings {
            MacSettingsView()
                .environmentObject(model)
        }
    }
}
