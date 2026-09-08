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
        case .amber: return Color(light: 0x895909, dark: 0xF3B755)
        case .ember: return Color(light: 0xA53851, dark: 0xF49AAA)
        case .violet: return Color(light: 0x7545B5, dark: 0xBC96F3)
        case .moss: return Color(light: 0x426B37, dark: 0x94BD83)
        case .slate: return Color(light: 0x4A6076, dark: 0x8AA3BB)
        }
    }

    /// The instrument face always has dark ink behind its illuminated marks.
    var instrumentColor: Color {
        switch self {
        case .amber: return Color(light: 0xEAB866, dark: 0xEAB866)
        case .ember: return Color(light: 0xF49AAA, dark: 0xF49AAA)
        case .violet: return Color(light: 0xBC96F3, dark: 0xBC96F3)
        case .moss: return Color(light: 0xA8C990, dark: 0xA8C990)
        case .slate: return Color(light: 0xA8BFD4, dark: 0xA8BFD4)
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
