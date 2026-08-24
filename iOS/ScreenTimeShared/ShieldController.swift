import Foundation
import ManagedSettings

/// Why the shield is currently up. Multiple reasons can be active at once
/// (e.g. quiet hours + budget exhausted); the shield stays up until the set
/// is empty. Both the app and the DeviceActivityMonitor extension use this,
/// coordinating through app-group defaults.
enum ShieldReason: String, CaseIterable {
    case focus   // user tapped "Focus now"
    case budget  // daily noise budget exhausted
    case quiet   // scheduled quiet hours

    var explanation: String {
        switch self {
        case .focus: return "YOU turned Focus on. You meant it. Get out of here."
        case .budget: return "Budget's SPENT. You set this limit for a reason. See you tomorrow."
        case .quiet: return "It's quiet hours. Nothing good is happening in there. Go to bed."
        }
    }
}

enum ShieldController {
    private static let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("noisegate"))

    static func activeReasons() -> Set<ShieldReason> {
        let raw = AppGroup.defaults.stringArray(forKey: StoreKey.shieldReasons) ?? []
        return Set(raw.compactMap(ShieldReason.init(rawValue:)))
    }

    static func add(_ reason: ShieldReason) {
        var reasons = activeReasons()
        reasons.insert(reason)
        persist(reasons)
        apply(reasons)
    }

    static func remove(_ reason: ShieldReason) {
        var reasons = activeReasons()
        reasons.remove(reason)
        persist(reasons)
        apply(reasons)
    }

    /// Re-applies the shield from the persisted state — call after the noise
    /// selection changes so the shield covers the new set of apps.
    static func refresh() {
        apply(activeReasons())
    }

    private static func persist(_ reasons: Set<ShieldReason>) {
        AppGroup.defaults.set(reasons.map(\.rawValue).sorted(), forKey: StoreKey.shieldReasons)
    }

    private static func apply(_ reasons: Set<ShieldReason>) {
        guard !reasons.isEmpty else {
            store.clearAllSettings()
            return
        }
        let selection = SelectionStore.noise()
        store.shield.applications = selection.applicationTokens.isEmpty
            ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil : selection.webDomainTokens
    }
}
