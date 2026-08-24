import SwiftUI

@main
struct NoiseGateApp: App {
    @StateObject private var model = ScreenTimeModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
