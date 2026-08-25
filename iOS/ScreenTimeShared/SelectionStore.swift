import FamilyControls
import Foundation
import ManagedSettings

/// Tokens toggled off without removing them from the system picker.
/// Tolerant decoding preserves v1 values when web-domain pausing is added.
struct PausedTokens: Codable, Equatable {
    var applications: Set<ApplicationToken> = []
    var webDomains: Set<WebDomainToken> = []
    /// When a paused token stops being paused. A token that is paused but
    /// absent here never expires, which is how every v1 pause was stored —
    /// so old data keeps behaving exactly as it did.
    var applicationExpiry: [ApplicationToken: Date] = [:]
    var webDomainExpiry: [WebDomainToken: Date] = [:]

    private enum CodingKeys: String, CodingKey {
        case applications
        case webDomains
        case applicationExpiry
        case webDomainExpiry
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
        applicationExpiry = try c.decodeIfPresent(
            [ApplicationToken: Date].self,
            forKey: .applicationExpiry
        ) ?? [:]
        webDomainExpiry = try c.decodeIfPresent(
            [WebDomainToken: Date].self,
            forKey: .webDomainExpiry
        ) ?? [:]
    }

    /// How long a pause lasts. "Indefinitely" is still the default, because a
    /// pause the owner has to remember to undo is the one they asked for when
    /// they said "stop counting this".
    enum Duration: String, CaseIterable, Identifiable {
        case today
        case week
        case indefinitely

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return "Until tomorrow"
            case .week: return "For a week"
            case .indefinitely: return "Until I turn it back on"
            }
        }

        /// The moment the pause lifts, or nil when it never does.
        func end(from now: Date = .now, calendar: Calendar = .current) -> Date? {
            switch self {
            case .today:
                let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
                return calendar.startOfDay(for: tomorrow)
            case .week:
                return calendar.date(byAdding: .day, value: 7, to: now)
            case .indefinitely:
                return nil
            }
        }
    }

    mutating func pause(application token: ApplicationToken, until end: Date?) {
        applications.insert(token)
        applicationExpiry[token] = end
    }

    mutating func pause(webDomain token: WebDomainToken, until end: Date?) {
        webDomains.insert(token)
        webDomainExpiry[token] = end
    }

    mutating func resume(application token: ApplicationToken) {
        applications.remove(token)
        applicationExpiry[token] = nil
    }

    mutating func resume(webDomain token: WebDomainToken) {
        webDomains.remove(token)
        webDomainExpiry[token] = nil
    }

    /// Lifts every pause whose end has passed. Returns true when anything
    /// changed, so the caller can persist and rebuild monitoring.
    @discardableResult
    mutating func expire(now: Date = .now) -> Bool {
        var changed = false
        for (token, end) in applicationExpiry where end <= now {
            applications.remove(token)
            applicationExpiry[token] = nil
            changed = true
        }
        for (token, end) in webDomainExpiry where end <= now {
            webDomains.remove(token)
            webDomainExpiry[token] = nil
            changed = true
        }
        // An expiry for a token that is no longer paused is dead weight.
        applicationExpiry = applicationExpiry.filter { applications.contains($0.key) }
        webDomainExpiry = webDomainExpiry.filter { webDomains.contains($0.key) }
        return changed
    }

    func expiry(forApplication token: ApplicationToken) -> Date? {
        applicationExpiry[token]
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

    /// Reads the stored pauses with any expired ones already lifted, writing
    /// the pruned value back so the expiry happens once rather than on every
    /// read. Monitoring is flagged for rebuild because the effective token
    /// set just widened.
    static func pausedDistractions(now: Date = .now) -> PausedTokens {
        expired(forKey: StoreKey.pausedDistractions, now: now)
    }

    static func pausedMessages(now: Date = .now) -> PausedTokens {
        expired(forKey: StoreKey.pausedMessages, now: now)
    }

    private static func expired(forKey key: String, now: Date) -> PausedTokens {
        var paused = SharedStore.shared.load(
            PausedTokens.self,
            forKey: key
        ) ?? PausedTokens()
        guard paused.expire(now: now) else { return paused }
        SharedStore.shared.save(paused, forKey: key)
        SharedStore.shared.saveBool(true, forKey: StoreKey.monitoringNeedsReconfigure)
        return paused
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
