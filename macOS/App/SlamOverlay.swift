import AppKit
import SwiftUI

/// Full-screen, click-through red slab flashed whenever a blocked noise app
/// comes to the front. Impossible to miss, gone in 2.5 seconds, and it can't
/// steal your clicks — it's pure theater with a message.
@MainActor
final class SlamOverlay {
    static let shared = SlamOverlay()
    private var window: NSWindow?
    private var dismissTask: Task<Void, Never>?

    func slam(appName: String, reason: String) {
        dismissTask?.cancel()
        guard let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.frame else { return }

        let win = window ?? makeWindow()
        window = win
        win.setFrame(screenFrame, display: true)
        win.contentView = NSHostingView(rootView: SlamView(appName: appName, reason: reason))
        win.orderFrontRegardless()

        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.window?.orderOut(nil)
        }
    }

    private func makeWindow() -> NSWindow {
        let win = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.level = .screenSaver
        win.isOpaque = false
        win.backgroundColor = .clear
        win.ignoresMouseEvents = true
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return win
    }
}

struct SlamView: View {
    let appName: String
    let reason: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [.red, Color(red: 0.55, green: 0, blue: 0)],
                           startPoint: .top, endPoint: .bottom)
                .opacity(0.92)
            VStack(spacing: 18) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 90, weight: .black))
                Text("NOPE.")
                    .font(.system(size: 110, weight: .black, design: .rounded))
                Text("\(appName) is blocked. \(reason)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
            }
            .foregroundStyle(.white)
        }
        .ignoresSafeArea()
    }
}
