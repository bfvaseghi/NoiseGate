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
}
