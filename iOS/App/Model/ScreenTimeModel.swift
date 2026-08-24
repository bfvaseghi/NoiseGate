import Foundation
import SwiftUI
import FamilyControls
import ManagedSettings
import DeviceActivity
import UserNotifications
import WidgetKit

extension DeviceActivityName {
    /// All-day monitoring window carrying the budget threshold events.
    static let daily = Self("daily")
}

/// Event names encode category + percent so the monitor extension can decode
/// them without extra state: "noise.p80" = noise budget reached 80%.
enum ThresholdEvent {
    static func name(kind: String, percent: Int) -> DeviceActivityEvent.Name {
        DeviceActivityEvent.Name("\(kind).p\(percent)")
    }
}

@MainActor
final class ScreenTimeModel: ObservableObject {
    @Published var noiseSelection: FamilyActivitySelection = SelectionStore.noise()
    @Published var messagesSelection: FamilyActivitySelection = SelectionStore.messages()
    @Published var mutedNoise: MutedTokens = SelectionStore.mutedNoise()
    @Published var mutedMessages: MutedTokens = SelectionStore.mutedMessages()
    @Published var config: BudgetConfig = BudgetConfig.load()
    @Published var isAuthorized: Bool = AuthorizationCenter.shared.authorizationStatus == .approved
    @Published var lastError: String?

    private let center = DeviceActivityCenter()

    // MARK: - Active (non-muted) token sets

    var activeNoiseApps: Set<ApplicationToken> {
        noiseSelection.applicationTokens.subtracting(mutedNoise.applications)
    }
    var activeNoiseCategories: Set<ActivityCategoryToken> {
        noiseSelection.categoryTokens.subtracting(mutedNoise.categories)
    }
    var activeMessagesApps: Set<ApplicationToken> {
        messagesSelection.applicationTokens.subtracting(mutedMessages.applications)
    }
    var activeMessagesCategories: Set<ActivityCategoryToken> {
        messagesSelection.categoryTokens.subtracting(mutedMessages.categories)
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = true
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            applyChanges()
        } catch {
            lastError = "Screen Time permission was not granted: \(error.localizedDescription)"
        }
    }

    // MARK: - Per-app toggles (paused, not deleted)

    func setNoiseApp(_ token: ApplicationToken, tracked: Bool) {
        if tracked { mutedNoise.applications.remove(token) }
        else { mutedNoise.applications.insert(token) }
        applyChanges()
    }

    func setNoiseCategory(_ token: ActivityCategoryToken, tracked: Bool) {
        if tracked { mutedNoise.categories.remove(token) }
        else { mutedNoise.categories.insert(token) }
        applyChanges()
    }

    func setMessagesApp(_ token: ApplicationToken, tracked: Bool) {
        if tracked { mutedMessages.applications.remove(token) }
        else { mutedMessages.applications.insert(token) }
        applyChanges()
    }

    func setMessagesCategory(_ token: ActivityCategoryToken, tracked: Bool) {
        if tracked { mutedMessages.categories.remove(token) }
        else { mutedMessages.categories.insert(token) }
        applyChanges()
    }

    // MARK: - Persist + (re)schedule

    /// Saves selections, muted sets, and config, then restarts DeviceActivity
    /// monitoring with threshold events built from the *active* tokens only.
    /// Muted apps are invisible to monitoring — nothing about them is recorded.
    func applyChanges() {
        // Prune muted tokens whose apps were removed from the selection.
        mutedNoise.applications.formIntersection(noiseSelection.applicationTokens)
        mutedNoise.categories.formIntersection(noiseSelection.categoryTokens)
        mutedMessages.applications.formIntersection(messagesSelection.applicationTokens)
        mutedMessages.categories.formIntersection(messagesSelection.categoryTokens)

        SelectionStore.saveNoise(noiseSelection)
        SelectionStore.saveMessages(messagesSelection)
        SelectionStore.saveMutedNoise(mutedNoise)
        SelectionStore.saveMutedMessages(mutedMessages)
        config.save()

        var snap = UsageSnapshot.loadToday()
        snap.noiseBudgetMinutes = config.noiseBudgetMinutes
        snap.messagesBudgetMinutes = config.messagesBudgetMinutes
        snap.isFloor = true
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()

        guard isAuthorized else { return }
        restartMonitoring()
    }

    private func restartMonitoring() {
        center.stopMonitoring()

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        let allPercents = BudgetConfig.progressPercents + BudgetConfig.overtimePercents

        if !activeNoiseApps.isEmpty || !activeNoiseCategories.isEmpty {
            for pct in allPercents {
                events[ThresholdEvent.name(kind: "noise", percent: pct)] = DeviceActivityEvent(
                    applications: activeNoiseApps,
                    categories: activeNoiseCategories,
                    webDomains: noiseSelection.webDomainTokens,
                    threshold: DateComponents(minute: max(1, config.noiseBudgetMinutes * pct / 100))
                )
            }
        }
        if !activeMessagesApps.isEmpty || !activeMessagesCategories.isEmpty {
            for pct in allPercents {
                events[ThresholdEvent.name(kind: "msg", percent: pct)] = DeviceActivityEvent(
                    applications: activeMessagesApps,
                    categories: activeMessagesCategories,
                    webDomains: messagesSelection.webDomainTokens,
                    threshold: DateComponents(minute: max(1, config.messagesBudgetMinutes * pct / 100))
                )
            }
        }

        guard !events.isEmpty else { return }
        let allDay = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        do {
            try center.startMonitoring(.daily, during: allDay, events: events)
        } catch {
            lastError = "Could not start monitoring: \(error.localizedDescription)"
        }
    }
}

extension FamilyActivitySelection {
    var isEmpty: Bool {
        applicationTokens.isEmpty && categoryTokens.isEmpty && webDomainTokens.isEmpty
    }
}
