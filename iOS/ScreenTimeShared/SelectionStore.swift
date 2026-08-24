import Foundation
import FamilyControls
import ManagedSettings

/// Persists the user's app selections (which apps count as "noise" and which
/// count as "messages") in the app group so extensions can read them.
/// `FamilyActivitySelection` is Codable, but its tokens are opaque — only
/// Screen Time system UI and APIs can interpret them. NoiseGate never sees
/// which apps you actually picked; that's the point.
///
/// Alongside each selection lives a `MutedTokens` set: apps/categories the
/// user has toggled OFF without removing them from the list. Muted tokens are
/// excluded from monitoring and from the usage reports — paused, not deleted.
struct MutedTokens: Codable, Equatable {
    var applications: Set<ApplicationToken> = []
    var categories: Set<ActivityCategoryToken> = []
}

enum SelectionStore {
    static func noise() -> FamilyActivitySelection {
        AppGroup.defaults.codable(FamilyActivitySelection.self, forKey: StoreKey.noiseSelection)
            ?? FamilyActivitySelection()
    }

    static func messages() -> FamilyActivitySelection {
        AppGroup.defaults.codable(FamilyActivitySelection.self, forKey: StoreKey.messagesSelection)
            ?? FamilyActivitySelection()
    }

    static func mutedNoise() -> MutedTokens {
        AppGroup.defaults.codable(MutedTokens.self, forKey: StoreKey.mutedNoise) ?? MutedTokens()
    }

    static func mutedMessages() -> MutedTokens {
        AppGroup.defaults.codable(MutedTokens.self, forKey: StoreKey.mutedMessages) ?? MutedTokens()
    }

    static func saveNoise(_ selection: FamilyActivitySelection) {
        AppGroup.defaults.setCodable(selection, forKey: StoreKey.noiseSelection)
    }

    static func saveMessages(_ selection: FamilyActivitySelection) {
        AppGroup.defaults.setCodable(selection, forKey: StoreKey.messagesSelection)
    }

    static func saveMutedNoise(_ muted: MutedTokens) {
        AppGroup.defaults.setCodable(muted, forKey: StoreKey.mutedNoise)
    }

    static func saveMutedMessages(_ muted: MutedTokens) {
        AppGroup.defaults.setCodable(muted, forKey: StoreKey.mutedMessages)
    }
}
