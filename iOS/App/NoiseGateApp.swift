import SwiftUI

@main
struct NoiseGateApp: App {
    @StateObject private var model = ScreenTimeModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .task { await model.refreshAuthorization() }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    // A pause with an end date can lapse while the app is
                    // closed; nothing else is running to notice.
                    model.expirePauses()
                    Task { await model.refreshAuthorization() }
                }
        }
    }
}
