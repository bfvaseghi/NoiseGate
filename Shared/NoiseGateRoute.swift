import Foundation

/// Stable routes used by widgets to open the relevant part of the iPhone app.
enum NoiseGateRoute: String, CaseIterable, Equatable {
    static let scheme = "noisegate"

    case today
    case apps
    case budgets

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              url.user == nil,
              url.password == nil,
              url.port == nil,
              url.path.isEmpty,
              url.query == nil,
              url.fragment == nil,
              let host = url.host?.lowercased(),
              let route = Self(rawValue: host) else { return nil }
        self = route
    }

    var url: URL {
        URL(string: "\(Self.scheme)://\(rawValue)")!
    }

    /// A Shortcut cannot open a URL on the app's behalf, so it leaves the
    /// route here and the app picks it up the moment it becomes active. This
    /// works for a cold launch as well as a resume.
    func requestOpen() {
        SharedStore.shared.save(rawValue, forKey: StoreKey.pendingRoute)
    }

    /// Reads and clears any route a Shortcut left behind.
    static func consumePending() -> NoiseGateRoute? {
        guard let raw = SharedStore.shared.load(String.self, forKey: StoreKey.pendingRoute),
              let route = NoiseGateRoute(rawValue: raw) else { return nil }
        SharedStore.shared.removeValue(forKey: StoreKey.pendingRoute)
        return route
    }
}
