import SwiftUI

/// User-selectable accent for the Distractions ledger. Every option is tuned
/// to stay legible on the warm paper ground in both appearances and to remain
/// clearly distinct from the fixed Messages teal and the over-budget red.
enum AccentTheme: String, CaseIterable, Identifiable, Sendable {
    case amber
    case ember
    case violet
    case moss
    case slate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .amber: return "Amber"
        case .ember: return "Ember"
        case .violet: return "Violet"
        case .moss: return "Moss"
        case .slate: return "Slate"
        }
    }

    var color: Color {
        switch self {
        case .amber: return Color(light: 0xE07C0E, dark: 0xF59A2E)
        case .ember: return Color(light: 0xD1495B, dark: 0xEE6B7C)
        case .violet: return Color(light: 0x7C4DBE, dark: 0xA579E4)
        case .moss: return Color(light: 0x4F7942, dark: 0x77A566)
        case .slate: return Color(light: 0x4A6076, dark: 0x8AA3BB)
        }
    }

    /// Read straight from the app-group defaults rather than through
    /// `SharedStore`: this is touched inside view bodies, and taking the
    /// cross-process file lock on every render would be far too expensive.
    /// A single-value write can't tear, so the plain read is safe here.
    static var current: AccentTheme {
        AppGroup.defaults.string(forKey: StoreKey.accentTheme)
            .flatMap(AccentTheme.init(rawValue:)) ?? .amber
    }

    static func select(_ theme: AccentTheme) {
        AppGroup.defaults.set(theme.rawValue, forKey: StoreKey.accentTheme)
    }
}
