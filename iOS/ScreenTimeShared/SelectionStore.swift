import FamilyControls
import Foundation
import ManagedSettings

/// Tokens toggled off without removing them from the system picker.
/// Tolerant decoding preserves v1 values when web-domain pausing is added.
struct PausedTokens: Codable, Equatable {
    var applications: Set<ApplicationToken> = []
    var webDomains: Set<WebDomainToken> = []

    private enum CodingKeys: String, CodingKey {
        case applications
        case webDomains
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        applications = try c.decodeIfPresent(
            Set<ApplicationToken>.self,
            forKey: .applications
        ) ?? []
        webDomains = try c.decodeIfPresent(
            Set<WebDomainToken>.self,
            forKey: .webDomains
        ) ?? []
    }
}

/// Screen Time selections are opaque. The app can compare tokens and hand
/// them back to Apple's APIs, but it cannot inspect a token to learn the app.
enum SelectionStore {
    static func hasSameTokens(
        _ lhs: FamilyActivitySelection,
        _ rhs: FamilyActivitySelection
    ) -> Bool {
        lhs.applicationTokens == rhs.applicationTokens
            && lhs.categoryTokens == rhs.categoryTokens
            && lhs.webDomainTokens == rhs.webDomainTokens
    }

    static func distractions() -> FamilyActivitySelection {
        let stored = SharedStore.shared.load(
            FamilyActivitySelection.self,
            forKey: StoreKey.distractionSelection
        ) ?? emptySelection
        let safe = sanitizeDistractions(stored)
        if !stored.categoryTokens.isEmpty {
            saveDistractions(safe)
            SharedStore.shared.saveBool(
                true,
                forKey: StoreKey.selectionMigrationNoticePending
            )
        }
        return safe
    }

    static func messages() -> FamilyActivitySelection {
        let stored = SharedStore.shared.load(
            FamilyActivitySelection.self,
            forKey: StoreKey.messagesSelection
        ) ?? emptySelection
        let safe = sanitizeMessages(stored)
        if !stored.categoryTokens.isEmpty || !stored.webDomainTokens.isEmpty {
            saveMessages(safe)
            SharedStore.shared.saveBool(
                true,
                forKey: StoreKey.selectionMigrationNoticePending
            )
        }
        return safe
    }

    static func pausedDistractions() -> PausedTokens {
        SharedStore.shared.load(
            PausedTokens.self,
            forKey: StoreKey.pausedDistractions
        ) ?? PausedTokens()
    }

    static func pausedMessages() -> PausedTokens {
        SharedStore.shared.load(
            PausedTokens.self,
            forKey: StoreKey.pausedMessages
        ) ?? PausedTokens()
    }

    static func saveDistractions(_ selection: FamilyActivitySelection) {
        SharedStore.shared.save(
            sanitizeDistractions(selection),
            forKey: StoreKey.distractionSelection
        )
    }

    static func saveMessages(_ selection: FamilyActivitySelection) {
        SharedStore.shared.save(
            sanitizeMessages(selection),
            forKey: StoreKey.messagesSelection
        )
    }

    static func savePausedDistractions(_ paused: PausedTokens) {
        SharedStore.shared.save(paused, forKey: StoreKey.pausedDistractions)
    }

    static func savePausedMessages(_ paused: PausedTokens) {
        SharedStore.shared.save(paused, forKey: StoreKey.pausedMessages)
    }

    /// Whole categories are deliberately rejected. Once Apple expands a
    /// category, its app/domain tokens cannot be distinguished from explicit
    /// picks, so keeping any part could silently make the total overinclusive.
    static func sanitizeDistractions(
        _ selection: FamilyActivitySelection
    ) -> FamilyActivitySelection {
        guard selection.categoryTokens.isEmpty else { return emptySelection }
        return selection
    }

    /// Messages is intentionally app-only. Categories or websites would turn
    /// a narrow messaging ledger into another broad Screen Time total.
    static func sanitizeMessages(
        _ selection: FamilyActivitySelection
    ) -> FamilyActivitySelection {
        guard selection.categoryTokens.isEmpty,
              selection.webDomainTokens.isEmpty else { return emptySelection }
        return selection
    }

    private static var emptySelection: FamilyActivitySelection {
        FamilyActivitySelection(includeEntireCategory: false)
    }
}

extension FamilyActivitySelection {
    var isEmpty: Bool {
        applicationTokens.isEmpty && categoryTokens.isEmpty && webDomainTokens.isEmpty
    }
}
