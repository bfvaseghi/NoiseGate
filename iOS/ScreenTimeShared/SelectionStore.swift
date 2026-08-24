import Foundation
import FamilyControls

/// Persists the user's app selections (which apps count as "noise" and which
/// count as "messages") in the app group so extensions can read them.
/// `FamilyActivitySelection` is Codable, but its tokens are opaque — only
/// Screen Time system UI and APIs can interpret them. NoiseGate never sees
/// which apps you actually picked; that's the point.
enum SelectionStore {
    static func noise() -> FamilyActivitySelection {
        AppGroup.defaults.codable(FamilyActivitySelection.self, forKey: StoreKey.noiseSelection)
            ?? FamilyActivitySelection()
    }

    static func messages() -> FamilyActivitySelection {
        AppGroup.defaults.codable(FamilyActivitySelection.self, forKey: StoreKey.messagesSelection)
            ?? FamilyActivitySelection()
    }

    static func saveNoise(_ selection: FamilyActivitySelection) {
        AppGroup.defaults.setCodable(selection, forKey: StoreKey.noiseSelection)
    }

    static func saveMessages(_ selection: FamilyActivitySelection) {
        AppGroup.defaults.setCodable(selection, forKey: StoreKey.messagesSelection)
    }
}
