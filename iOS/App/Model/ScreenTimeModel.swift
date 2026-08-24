import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import SwiftUI
import UserNotifications
import WidgetKit

@MainActor
final class ScreenTimeModel: ObservableObject {
    @Published var distractionSelection = SelectionStore.distractions()
    @Published var messagesSelection = SelectionStore.messages()
    @Published var pausedDistractions = SelectionStore.pausedDistractions()
    @Published var pausedMessages = SelectionStore.pausedMessages()
    @Published var config = BudgetConfig.load()
    @Published private(set) var authorizationStatus =
        AuthorizationCenter.shared.authorizationStatus
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published var lastError: String?

    private let center = DeviceActivityCenter()
    private let store = SharedStore.shared
    private var restartTask: Task<Void, Never>?

    init() {
        if store.bool(forKey: StoreKey.selectionMigrationNoticePending) {
            store.saveBool(false, forKey: StoreKey.selectionMigrationNoticePending)
            lastError = "NoiseGate removed a legacy whole-category choice because it could include useful activity. Choose the individual apps you want to track again."
        }
    }

    var isAuthorized: Bool { authorizationStatus == .approved }

    // MARK: - Effective token sets

    var activeMessagesApps: Set<ApplicationToken> {
        messagesSelection.applicationTokens.subtracting(pausedMessages.applications)
    }

    /// Messages always wins if the same opaque app token appears in both
    /// lists, even while its Messages row is paused. Pausing therefore makes
    /// the app invisible instead of silently moving it into Distractions.
    var activeDistractionApps: Set<ApplicationToken> {
        distractionSelection.applicationTokens
            .subtracting(pausedDistractions.applications)
            .subtracting(messagesSelection.applicationTokens)
    }

    var activeDistractionWebDomains: Set<WebDomainToken> {
        distractionSelection.webDomainTokens.subtracting(pausedDistractions.webDomains)
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorizationStatus = AuthorizationCenter.shared.authorizationStatus
            guard isAuthorized else {
                pauseForRevokedAuthorization()
                return
            }
            if config.notificationsEnabled {
                await requestNotificationAuthorization()
            }
            applyTrackingChanges()
        } catch {
            authorizationStatus = AuthorizationCenter.shared.authorizationStatus
            pauseForRevokedAuthorization()
            lastError = "Screen Time access was not granted. Check Settings › Screen Time › Apps with Screen Time Access, then try again."
        }
    }

    func refreshAuthorization() async {
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus

        if notificationStatus == .denied && config.notificationsEnabled {
            config.notificationsEnabled = false
            savePreferences()
        }

        guard isAuthorized else {
            pauseForRevokedAuthorization()
            return
        }
        if store.load(Int.self, forKey: StoreKey.monitoringSchemaVersion)
            != ThresholdEvent.schemaVersion {
            store.saveBool(false, forKey: StoreKey.monitoringAcceptsCallbacks)
            store.saveBool(true, forKey: StoreKey.monitoringNeedsReconfigure)
            center.stopMonitoring([.daily])
        }
        let hasTrackedTokens = !activeDistractionApps.isEmpty
            || !activeDistractionWebDomains.isEmpty
            || !activeMessagesApps.isEmpty
        if store.bool(forKey: StoreKey.monitoringNeedsReconfigure)
            || (hasTrackedTokens && !center.activities.contains(.daily)) {
            scheduleMonitoringRestart()
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        if enabled {
            Task { await requestNotificationAuthorization() }
        } else {
            config.notificationsEnabled = false
            savePreferences()
        }
    }

    func setNotification(at percent: Int, enabled: Bool) {
        guard BudgetConfig.nudgePercents.contains(percent) else { return }
        if enabled { config.notifyAt.insert(percent) }
        else { config.notifyAt.remove(percent) }
        savePreferences()
    }

    func setOvertimeNotifications(_ enabled: Bool) {
        config.overtimeNotifications = enabled
        savePreferences()
    }

    private func requestNotificationAuthorization() async {
        do {
            let approved = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationStatus = settings.authorizationStatus
            config.notificationsEnabled = approved
            savePreferences()
            if !approved {
                lastError = "Notifications are off. NoiseGate will keep tracking, but iPhone settings must allow notifications before nudges can appear."
            }
        } catch {
            config.notificationsEnabled = false
            savePreferences()
            lastError = "Notification permission could not be requested. Tracking is still active."
        }
    }

    private func pauseForRevokedAuthorization() {
        restartTask?.cancel()
        store.saveBool(false, forKey: StoreKey.monitoringAcceptsCallbacks)
        center.stopMonitoring([.daily])
        updateSnapshot(resetProgress: false, monitoringIsActive: false)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Paused tokens

    func setDistractionApp(_ token: ApplicationToken, tracked: Bool) {
        if tracked { pausedDistractions.applications.remove(token) }
        else { pausedDistractions.applications.insert(token) }
        applyTrackingChanges()
    }

    func setDistractionWebDomain(_ token: WebDomainToken, tracked: Bool) {
        if tracked { pausedDistractions.webDomains.remove(token) }
        else { pausedDistractions.webDomains.insert(token) }
        applyTrackingChanges()
    }

    func setMessagesApp(_ token: ApplicationToken, tracked: Bool) {
        if tracked { pausedMessages.applications.remove(token) }
        else { pausedMessages.applications.insert(token) }
        applyTrackingChanges()
    }

    // MARK: - Settings and persistence

    func adjustBudget(_ keyPath: WritableKeyPath<BudgetConfig, Int>, by delta: Int) {
        config[keyPath: keyPath] = min(
            480,
            max(5, config[keyPath: keyPath] + delta)
        )
        applyTrackingChanges()
    }

    /// Call after a picker, pause toggle, or budget edit. Old checkpoint floors
    /// no longer describe the new rules, so they are cleared before monitoring
    /// is rebuilt. The replacement includes today's past activity so its
    /// checkpoint floor can be rebuilt under the new rules.
    func applyTrackingChanges() {
        let hadQueuedRestart = restartTask != nil
        restartTask?.cancel()
        store.saveBool(false, forKey: StoreKey.monitoringAcceptsCallbacks)
        store.saveBool(true, forKey: StoreKey.monitoringNeedsReconfigure)
        center.stopMonitoring([.daily])

        let rejectedDistractionCategory = !distractionSelection.categoryTokens.isEmpty
        let rejectedMessagesBreadth = !messagesSelection.categoryTokens.isEmpty
            || !messagesSelection.webDomainTokens.isEmpty

        distractionSelection = SelectionStore.sanitizeDistractions(distractionSelection)
        messagesSelection = SelectionStore.sanitizeMessages(messagesSelection)
        prunePausedTokens()
        persistSelections()
        config.save()
        updateSnapshot(resetProgress: true, monitoringIsActive: false)
        if !hadQueuedRestart {
            WidgetCenter.shared.reloadAllTimelines()
        }

        if rejectedDistractionCategory || rejectedMessagesBreadth {
            lastError = "Choose individual apps for Distractions and Messages. Whole categories are excluded because they can pull useful activity back into the total."
        }
        guard isAuthorized else { return }
        scheduleMonitoringRestart()
    }

    /// Notification choices do not change usage thresholds, so saving them
    /// must not restart DeviceActivity or erase today's checkpoint floor.
    func savePreferences() {
        config.save()
        updateSnapshot(resetProgress: false, monitoringIsActive: nil)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func persistSelections() {
        SelectionStore.saveDistractions(distractionSelection)
        SelectionStore.saveMessages(messagesSelection)
        SelectionStore.savePausedDistractions(pausedDistractions)
        SelectionStore.savePausedMessages(pausedMessages)
    }

    private func prunePausedTokens() {
        pausedDistractions.applications.formIntersection(
            distractionSelection.applicationTokens
        )
        pausedDistractions.webDomains.formIntersection(
            distractionSelection.webDomainTokens
        )
        pausedMessages.applications.formIntersection(messagesSelection.applicationTokens)
        pausedMessages.webDomains.removeAll()
    }

    @discardableResult
    private func updateSnapshot(
        resetProgress: Bool,
        monitoringIsActive: Bool?
    ) -> UsageSnapshot {
        let today = DayKey.today()
        if let previous = store.load(
            UsageSnapshot.self,
            forKey: StoreKey.usageSnapshot
        ) {
            HistoryStore.recordFinishedSnapshot(previous, today: today)
        }
        return store.update(
            UsageSnapshot.self,
            forKey: StoreKey.usageSnapshot,
            default: UsageSnapshot()
        ) { snapshot in
            if snapshot.dayKey != today {
                snapshot = UsageSnapshot(dayKey: today, isFloor: true)
            }
            if resetProgress {
                snapshot.distractionMinutes = 0
                snapshot.messagesMinutes = 0
            }
            snapshot.distractionBudgetMinutes = config.distractionBudgetMinutes
            snapshot.messagesBudgetMinutes = config.messagesBudgetMinutes
            snapshot.distractionsConfigured = !activeDistractionApps.isEmpty
                || !activeDistractionWebDomains.isEmpty
            snapshot.messagesConfigured = !activeMessagesApps.isEmpty
            snapshot.isFloor = true
            if let monitoringIsActive {
                snapshot.monitoringIsActive = monitoringIsActive
            }
            snapshot.updatedAt = .now
        }
    }

    // MARK: - DeviceActivity

    private func scheduleMonitoringRestart() {
        restartTask?.cancel()
        restartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.restartTask = nil
            self?.restartMonitoring()
        }
    }

    private func restartMonitoring() {
        store.saveBool(false, forKey: StoreKey.monitoringAcceptsCallbacks)
        store.saveBool(true, forKey: StoreKey.monitoringNeedsReconfigure)
        center.stopMonitoring([.daily])
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        let percents = BudgetConfig.progressPercents + BudgetConfig.overtimePercents
        let generation = (store.load(
            Int.self,
            forKey: StoreKey.monitoringGeneration
        ) ?? 0) + 1

        if !activeDistractionApps.isEmpty || !activeDistractionWebDomains.isEmpty {
            for percent in percents {
                events[ThresholdEvent.name(
                    kind: "distractions",
                    percent: percent,
                    generation: generation,
                    budgetMinutes: config.distractionBudgetMinutes
                )] = makeEvent(
                    applications: activeDistractionApps,
                    webDomains: activeDistractionWebDomains,
                    thresholdMinutes: ThresholdEvent.thresholdMinutes(
                        budget: config.distractionBudgetMinutes,
                        percent: percent
                    )
                )
            }
        }
        if !activeMessagesApps.isEmpty {
            for percent in percents {
                events[ThresholdEvent.name(
                    kind: "msg",
                    percent: percent,
                    generation: generation,
                    budgetMinutes: config.messagesBudgetMinutes
                )] = makeEvent(
                    applications: activeMessagesApps,
                    webDomains: [],
                    thresholdMinutes: ThresholdEvent.thresholdMinutes(
                        budget: config.messagesBudgetMinutes,
                        percent: percent
                    )
                )
            }
        }

        guard !events.isEmpty else {
            store.saveBool(false, forKey: StoreKey.monitoringAcceptsCallbacks)
            store.saveBool(false, forKey: StoreKey.monitoringNeedsReconfigure)
            store.save(
                ThresholdEvent.schemaVersion,
                forKey: StoreKey.monitoringSchemaVersion
            )
            store.removeValue(forKey: StoreKey.monitoringConfiguredAt)
            updateSnapshot(resetProgress: false, monitoringIsActive: false)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        let allDay = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
        store.save(Date(), forKey: StoreKey.monitoringConfiguredAt)
        store.save(generation, forKey: StoreKey.monitoringGeneration)
        store.saveBool(true, forKey: StoreKey.monitoringAcceptsCallbacks)
        do {
            try center.startMonitoring(.daily, during: allDay, events: events)
            store.saveBool(false, forKey: StoreKey.monitoringNeedsReconfigure)
            store.save(
                ThresholdEvent.schemaVersion,
                forKey: StoreKey.monitoringSchemaVersion
            )
            updateSnapshot(resetProgress: false, monitoringIsActive: true)
            WidgetCenter.shared.reloadAllTimelines()
            if lastError?.hasPrefix("Monitoring did not start.") == true {
                lastError = nil
            }
        } catch {
            store.saveBool(false, forKey: StoreKey.monitoringAcceptsCallbacks)
            store.saveBool(true, forKey: StoreKey.monitoringNeedsReconfigure)
            store.removeValue(forKey: StoreKey.monitoringConfiguredAt)
            updateSnapshot(resetProgress: false, monitoringIsActive: false)
            lastError = "Monitoring did not start. Confirm Screen Time access and the Family Controls capability for the app, monitor, and report targets."
        }
    }

    private func makeEvent(
        applications: Set<ApplicationToken>,
        webDomains: Set<WebDomainToken>,
        thresholdMinutes: Int
    ) -> DeviceActivityEvent {
        return DeviceActivityEvent(
            applications: applications,
            categories: [],
            webDomains: webDomains,
            threshold: DateComponents(minute: thresholdMinutes),
            includesPastActivity: true
        )
    }
}
