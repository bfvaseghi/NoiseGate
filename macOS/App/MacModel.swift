import AppKit
import Combine
import CoreGraphics
import Foundation
import ServiceManagement
import UserNotifications
import WidgetKit

/// Per-day time is classified when it accrues. Changing an app's list later
/// cannot erase or move time that was already recorded earlier in the day.
struct MacLedger: Codable {
    var dayKey: String
    var distractionSecondsByBundleID: [String: Double]
    var messagesSecondsByBundleID: [String: Double]
    var distractionBudgetMinutes: Int
    var messagesBudgetMinutes: Int

    /// Populated only while decoding the v1 bundle-id-only ledger.
    var legacyUnclassifiedSeconds: [String: Double] = [:]
    var wasLegacyFormat = false

    init(config: BudgetConfig, dayKey: String = DayKey.today()) {
        self.dayKey = dayKey
        distractionSecondsByBundleID = [:]
        messagesSecondsByBundleID = [:]
        distractionBudgetMinutes = config.distractionBudget(on: .now)
        messagesBudgetMinutes = config.messagesBudgetMinutes
    }

    private enum CodingKeys: String, CodingKey {
        case dayKey
        case distractionSecondsByBundleID
        case messagesSecondsByBundleID
        case distractionBudgetMinutes
        case messagesBudgetMinutes
        case seconds // v1 migration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = try c.decodeIfPresent(String.self, forKey: .dayKey) ?? DayKey.today()
        distractionSecondsByBundleID = try c.decodeIfPresent(
            [String: Double].self,
            forKey: .distractionSecondsByBundleID
        ) ?? [:]
        messagesSecondsByBundleID = try c.decodeIfPresent(
            [String: Double].self,
            forKey: .messagesSecondsByBundleID
        ) ?? [:]
        distractionBudgetMinutes = try c.decodeIfPresent(
            Int.self,
            forKey: .distractionBudgetMinutes
        ) ?? 45
        messagesBudgetMinutes = try c.decodeIfPresent(
            Int.self,
            forKey: .messagesBudgetMinutes
        ) ?? 60
        legacyUnclassifiedSeconds = try c.decodeIfPresent(
            [String: Double].self,
            forKey: .seconds
        ) ?? [:]
        wasLegacyFormat = c.contains(.seconds)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dayKey, forKey: .dayKey)
        try c.encode(distractionSecondsByBundleID, forKey: .distractionSecondsByBundleID)
        try c.encode(messagesSecondsByBundleID, forKey: .messagesSecondsByBundleID)
        try c.encode(distractionBudgetMinutes, forKey: .distractionBudgetMinutes)
        try c.encode(messagesBudgetMinutes, forKey: .messagesBudgetMinutes)
    }

    var distractionSeconds: Double {
        distractionSecondsByBundleID.values.reduce(0) { $0 + max(0, $1) }
    }

    var messagesSeconds: Double {
        messagesSecondsByBundleID.values.reduce(0) { $0 + max(0, $1) }
    }

    var dayRecord: DayRecord {
        DayRecord(
            dayKey: dayKey,
            distractionMinutes: Int(distractionSeconds / 60),
            messagesMinutes: Int(messagesSeconds / 60),
            distractionBudgetMinutes: distractionBudgetMinutes,
            messagesBudgetMinutes: messagesBudgetMinutes,
            isFloor: false
        )
    }

    /// Converts Claude's v1 bundle-only totals exactly once. Messages wins an
    /// overlap, matching the live accrual rule, and v1's missing targets come
    /// from the user's persisted configuration rather than fabricated defaults.
    mutating func migrateLegacy(
        config: BudgetConfig,
        distractionBundleIDs: Set<String>,
        messagesBundleIDs: Set<String>
    ) {
        guard wasLegacyFormat else { return }
        distractionBudgetMinutes = config.distractionBudgetMinutes
        messagesBudgetMinutes = config.messagesBudgetMinutes
        for (bundleID, seconds) in legacyUnclassifiedSeconds {
            if messagesBundleIDs.contains(bundleID) {
                messagesSecondsByBundleID[bundleID, default: 0] += max(0, seconds)
            } else if distractionBundleIDs.contains(bundleID) {
                distractionSecondsByBundleID[bundleID, default: 0] += max(0, seconds)
            }
        }
        legacyUnclassifiedSeconds.removeAll()
        wasLegacyFormat = false
    }
}

struct DiscoveredApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

struct MacSelections: Codable, Equatable {
    var distractions: Set<String>
    var messages: Set<String>
}

@MainActor
final class MacModel: NSObject, ObservableObject {
    @Published private(set) var config: BudgetConfig
    @Published private(set) var distractionBundleIDs: Set<String>
    @Published private(set) var messagesBundleIDs: Set<String>
    /// Published at minute granularity so the menu bar and popover do not
    /// redraw every five seconds.
    @Published private(set) var distractionMinutesToday = 0
    @Published private(set) var messagesMinutesToday = 0

    /// The Distractions target for today, which is the weekend one on a
    /// weekend. Views must read this rather than `config.distractionBudgetMinutes`,
    /// which is the weekday setting.
    var todayDistractionBudget: Int { config.distractionBudget(on: .now) }
    @Published private(set) var installedApps: [DiscoveredApp] = []
    @Published private(set) var isUserIdle = false
    @Published private(set) var isSessionActive = true
    @Published private(set) var activeAppName: String?
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var launchAtLoginEnabled = false
    @Published var lastError: String?

    private static let tickInterval: TimeInterval = 5
    private static let persistInterval: TimeInterval = 15
    private static let widgetReloadInterval: TimeInterval = 30
    private static let idleCutoff: TimeInterval = 120
    private static let anyInputEventType = CGEventType(rawValue: UInt32.max)!

    private let store = SharedStore.shared
    private let workspace = NSWorkspace.shared
    private var ledger: MacLedger
    private var timer: Timer?
    private var lastCheckpointAt: Date
    private var lastPersistedAt: Date
    private var observedBundleID: String?
    private var hasShutDown = false
    private var distractionSecondsToday: Double = 0
    private var messagesSecondsToday: Double = 0
    /// In-memory mirror avoids a locked app-group read on every tick after a
    /// milestone has already fired.
    private var nudgesSentToday: Set<String>

    var trackingDetail: String {
        guard isSessionActive else { return "Paused while this Mac is locked or asleep" }
        guard !isUserIdle else { return "Paused after two minutes without input" }
        guard let bundleID = observedBundleID else { return "Waiting for a foreground app" }
        if messagesBundleIDs.contains(bundleID) {
            return "Counting \(activeAppName ?? "this app") in Messages"
        }
        if distractionBundleIDs.contains(bundleID) {
            return "Counting \(activeAppName ?? "this app") in Distractions"
        }
        return "Unselected apps are ignored"
    }

    override init() {
        let loadedConfig = BudgetConfig.load()
        let storedSelections = SharedStore.shared.load(
            MacSelections.self,
            forKey: StoreKey.macSelections
        )
        var loadedDistractionBundleIDs = storedSelections?.distractions ?? Set(
            SharedStore.shared.stringArray(forKey: StoreKey.macDistractionApps) ?? []
        )
        let loadedMessagesBundleIDs = storedSelections?.messages ?? Set(
            SharedStore.shared.stringArray(forKey: StoreKey.macMessagesApps)
                ?? ["com.apple.MobileSMS", "com.apple.iChat"]
        )

        // Messages wins any v1 overlap and remains a separate ledger.
        loadedDistractionBundleIDs.subtract(loadedMessagesBundleIDs)

        config = loadedConfig
        distractionBundleIDs = loadedDistractionBundleIDs
        messagesBundleIDs = loadedMessagesBundleIDs

        var loadedLedger = SharedStore.shared.load(
            MacLedger.self,
            forKey: StoreKey.macLedger
        ) ?? MacLedger(config: loadedConfig)
        loadedLedger.migrateLegacy(
            config: loadedConfig,
            distractionBundleIDs: loadedDistractionBundleIDs,
            messagesBundleIDs: loadedMessagesBundleIDs
        )

        if loadedLedger.dayKey != DayKey.today() {
            HistoryStore.record(loadedLedger.dayRecord)
            loadedLedger = MacLedger(config: loadedConfig)
            SharedStore.shared.saveStringArray([], forKey: StoreKey.macNudgesSent)
        } else {
            // Recover cleanly if a prior budget save reached BudgetConfig but
            // the app exited before the current-day ledger target was flushed.
            loadedLedger.distractionBudgetMinutes = loadedConfig.distractionBudgetMinutes
            loadedLedger.messagesBudgetMinutes = loadedConfig.messagesBudgetMinutes
        }
        ledger = loadedLedger
        nudgesSentToday = Set(
            SharedStore.shared.stringArray(forKey: StoreKey.macNudgesSent) ?? []
        )

        let now = Date()
        lastCheckpointAt = now
        lastPersistedAt = now
        observedBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        super.init()
        UNUserNotificationCenter.current().delegate = self
        persistSelections()
        recomputeTotals()
        persistLedger()
        installObservers()
        startTicking()
        discoverApps()
        refreshLaunchAtLoginStatus()
        publishSnapshot(forceWidgetReload: true)

        if config.notificationsEnabled {
            Task { await requestNotificationAuthorization() }
        } else {
            Task { await refreshNotificationStatus() }
        }
    }

    // MARK: - User settings

    func toggleDistraction(_ bundleID: String) {
        checkpoint()
        if distractionBundleIDs.contains(bundleID) {
            distractionBundleIDs.remove(bundleID)
        } else {
            distractionBundleIDs.insert(bundleID)
            messagesBundleIDs.remove(bundleID)
        }
        persistSelections()
        discoverApps()
        publishSnapshot(forceWidgetReload: true)
    }

    func toggleMessages(_ bundleID: String) {
        checkpoint()
        if messagesBundleIDs.contains(bundleID) {
            messagesBundleIDs.remove(bundleID)
        } else {
            messagesBundleIDs.insert(bundleID)
            distractionBundleIDs.remove(bundleID)
        }
        persistSelections()
        discoverApps()
        publishSnapshot(forceWidgetReload: true)
    }

    func adjustBudget(_ keyPath: WritableKeyPath<BudgetConfig, Int>, by delta: Int) {
        checkpoint()
        config[keyPath: keyPath] = min(480, max(5, config[keyPath: keyPath] + delta))
        ledger.distractionBudgetMinutes = config.distractionBudget(on: .now)
        ledger.messagesBudgetMinutes = config.messagesBudgetMinutes
        saveConfigAndPublish()
        checkNudges()
    }

    func setNotification(at percent: Int, enabled: Bool) {
        guard BudgetConfig.nudgePercents.contains(percent) else { return }
        if enabled { config.notifyAt.insert(percent) }
        else { config.notifyAt.remove(percent) }
        saveConfigAndPublish()
    }

    func setOvertimeNotifications(_ enabled: Bool) {
        config.overtimeNotifications = enabled
        saveConfigAndPublish()
    }

    func setShowMinutesInMenuBar(_ enabled: Bool) {
        config.showMinutesInMenuBar = enabled
        saveConfigAndPublish()
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        if enabled {
            Task { await requestNotificationAuthorization() }
        } else {
            config.notificationsEnabled = false
            saveConfigAndPublish()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLoginStatus()
        } catch {
            refreshLaunchAtLoginStatus()
            lastError = "Launch at login could not be changed: \(error.localizedDescription)"
        }
    }

    private func saveConfigAndPublish() {
        config.save()
        persistLedger()
        publishSnapshot(forceWidgetReload: true)
    }

    private func persistSelections() {
        store.save(
            MacSelections(
                distractions: distractionBundleIDs,
                messages: messagesBundleIDs
            ),
            forKey: StoreKey.macSelections
        )
    }

    // MARK: - Tracking

    private func startTicking() {
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkpoint() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func checkpoint(at now: Date = Date()) {
        guard !hasShutDown else { return }
        let elapsed = min(max(0, now.timeIntervalSince(lastCheckpointAt)), 15)
        let accrualStart = now.addingTimeInterval(-elapsed)
        let idleSeconds = secondsSinceLastInput()
        isUserIdle = idleSeconds >= Self.idleCutoff

        let shouldAccrue = isSessionActive && !isUserIdle && elapsed > 0
        let currentDay = DayKey.today(now)
        var didRollOver = false

        if ledger.dayKey != currentDay,
           shouldAccrue,
           let boundary = DayKey.date(from: currentDay),
           boundary > accrualStart,
           boundary < now {
            accrue(
                boundary.timeIntervalSince(accrualStart),
                to: observedBundleID
            )
            didRollOver = rolloverIfNeeded(at: now)
            accrue(now.timeIntervalSince(boundary), to: observedBundleID)
        } else {
            didRollOver = rolloverIfNeeded(at: now)
            if shouldAccrue {
                accrue(elapsed, to: observedBundleID)
            }
        }

        lastCheckpointAt = now
        let frontmost = workspace.frontmostApplication
        observedBundleID = frontmost?.bundleIdentifier
        activeAppName = frontmost?.localizedName
        recomputeTotals()
        checkNudges()

        if didRollOver || now.timeIntervalSince(lastPersistedAt) >= Self.persistInterval {
            lastPersistedAt = now
            persistLedger()
            publishSnapshot(forceWidgetReload: didRollOver)
        }
    }

    private func accrue(_ seconds: TimeInterval, to bundleID: String?) {
        guard seconds > 0, let bundleID else { return }
        if messagesBundleIDs.contains(bundleID) {
            ledger.messagesSecondsByBundleID[bundleID, default: 0] += seconds
        } else if distractionBundleIDs.contains(bundleID) {
            ledger.distractionSecondsByBundleID[bundleID, default: 0] += seconds
        }
    }

    @discardableResult
    private func rolloverIfNeeded(at now: Date) -> Bool {
        let currentDay = DayKey.today(now)
        guard ledger.dayKey != currentDay else { return false }
        HistoryStore.record(ledger.dayRecord)
        ledger = MacLedger(config: config, dayKey: currentDay)
        nudgesSentToday = []
        store.saveStringArray([], forKey: StoreKey.macNudgesSent)
        return true
    }

    private func recomputeTotals() {
        distractionSecondsToday = ledger.distractionSeconds
        messagesSecondsToday = ledger.messagesSeconds
        let distractions = Int(distractionSecondsToday / 60)
        let messages = Int(messagesSecondsToday / 60)
        if distractions != distractionMinutesToday {
            distractionMinutesToday = distractions
        }
        if messages != messagesMinutesToday {
            messagesMinutesToday = messages
        }
    }

    private func secondsSinceLastInput() -> Double {
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: Self.anyInputEventType
        )
    }

    private func installObservers() {
        let center = workspace.notificationCenter
        center.addObserver(
            self,
            selector: #selector(frontmostApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(sessionDidResign(_:)),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive(_:)),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(sessionDidResign(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(sessionDidBecomeActive(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate(_:)),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func frontmostApplicationChanged(_ notification: Notification) {
        checkpoint()
    }

    @objc private func sessionDidResign(_ notification: Notification) {
        checkpoint()
        isSessionActive = false
        persistLedger()
        publishSnapshot(forceWidgetReload: true)
    }

    @objc private func sessionDidBecomeActive(_ notification: Notification) {
        isSessionActive = true
        lastCheckpointAt = Date()
        observedBundleID = workspace.frontmostApplication?.bundleIdentifier
        checkpoint()
    }

    @objc private func applicationWillTerminate(_ notification: Notification) {
        guard !hasShutDown else { return }
        checkpoint()
        hasShutDown = true
        timer?.invalidate()
        persistLedger()
        publishSnapshot(monitoringIsActive: false, forceWidgetReload: true)
    }

    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        refreshLaunchAtLoginStatus()
        Task { await refreshNotificationStatus() }
    }

    // MARK: - Notifications

    private func checkNudges() {
        nudgeIfCrossed(
            kind: "distractions",
            seconds: distractionSecondsToday,
            budget: config.distractionBudget(on: .now)
        )
        nudgeIfCrossed(
            kind: "msg",
            seconds: messagesSecondsToday,
            budget: config.messagesBudgetMinutes
        )
    }

    /// If a launch or budget edit crosses several milestones at once, send
    /// only the highest one and mark lower milestones consumed. This avoids a
    /// notification burst while keeping normal day-long crossings intact.
    private func nudgeIfCrossed(kind: String, seconds: Double, budget: Int) {
        guard config.notificationsEnabled, budget > 0 else { return }
        let allPercents = BudgetConfig.nudgePercents + BudgetConfig.overtimePercents
        let crossed = allPercents.filter {
            seconds * 100 >= Double(budget * 60 * $0) && config.notifies(atPercent: $0)
        }
        guard let highest = crossed.max() else { return }

        let day = DayKey.today()
        let highestKey = "\(kind).\(highest)@\(day)"
        let legacyKey = kind == "distractions"
            ? "noise.\(highest)@\(day)" : nil
        let alreadySent = nudgesSentToday.contains(highestKey)
            || (legacyKey.map { nudgesSentToday.contains($0) } ?? false)
        guard !alreadySent else { return }

        var shouldNotify = false
        nudgesSentToday = store.updateStringSet(
            forKey: StoreKey.macNudgesSent
        ) { sent in
            let legacyWasSent = legacyKey.map { sent.contains($0) } ?? false
            shouldNotify = !sent.contains(highestKey) && !legacyWasSent
            for percent in crossed {
                sent.insert("\(kind).\(percent)@\(day)")
            }
        }
        guard shouldNotify,
              let text = NudgeText.notification(
                kind: kind,
                percent: highest,
                budgetMinutes: budget
              ) else { return }

        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default
        content.threadIdentifier = "noisegate.\(kind)"
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "noisegate.\(kind).\(highest)@\(day)",
                content: content,
                trigger: nil
            )
        )
    }

    private func requestNotificationAuthorization() async {
        do {
            let approved = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            config.notificationsEnabled = approved
            await refreshNotificationStatus()
            saveConfigAndPublish()
            if !approved {
                lastError = "Notifications are off. Mac tracking and widgets continue normally."
            }
        } catch {
            config.notificationsEnabled = false
            saveConfigAndPublish()
            lastError = "Notification permission could not be requested. Tracking is still active."
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
        if notificationStatus == .denied && config.notificationsEnabled {
            config.notificationsEnabled = false
            saveConfigAndPublish()
        }
    }

    // MARK: - Snapshot and history

    var weekRecords: [DayRecord] {
        var records = HistoryStore.lastDays(7).filter { $0.dayKey != ledger.dayKey }
        records = Array(records.suffix(6))
        records.append(ledger.dayRecord)
        return records
    }

    private func persistLedger() {
        store.save(ledger, forKey: StoreKey.macLedger)
    }

    private func publishSnapshot(
        monitoringIsActive: Bool = true,
        forceWidgetReload: Bool = false
    ) {
        let now = Date()
        let snapshot = UsageSnapshot(
            dayKey: ledger.dayKey,
            distractionMinutes: distractionMinutesToday,
            messagesMinutes: messagesMinutesToday,
            distractionBudgetMinutes: config.distractionBudget(on: .now),
            messagesBudgetMinutes: config.messagesBudgetMinutes,
            distractionsConfigured: !distractionBundleIDs.isEmpty,
            messagesConfigured: !messagesBundleIDs.isEmpty,
            isFloor: false,
            monitoringIsActive: monitoringIsActive,
            updatedAt: now
        )
        let current = store.load(
            UsageSnapshot.self,
            forKey: StoreKey.usageSnapshot
        )
        let displayChanged = current.map {
            $0.dayKey != snapshot.dayKey
                || $0.distractionMinutes != snapshot.distractionMinutes
                || $0.messagesMinutes != snapshot.messagesMinutes
                || $0.distractionBudgetMinutes != snapshot.distractionBudgetMinutes
                || $0.messagesBudgetMinutes != snapshot.messagesBudgetMinutes
                || $0.distractionsConfigured != snapshot.distractionsConfigured
                || $0.messagesConfigured != snapshot.messagesConfigured
                || $0.isFloor != snapshot.isFloor
                || $0.monitoringIsActive != snapshot.monitoringIsActive
        } ?? true
        let heartbeatDue = current.map {
            now.timeIntervalSince($0.updatedAt) >= Self.widgetReloadInterval
        } ?? true
        guard forceWidgetReload || displayChanged || heartbeatDue else { return }
        snapshot.save()

        if forceWidgetReload || displayChanged {
            WidgetCenter.shared.reloadTimelines(ofKind: "NoiseGateMacWidget")
        }
    }

    // MARK: - App discovery

    func discoverApps() {
        let running = workspace.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                app.bundleIdentifier.map {
                    DiscoveredApp(bundleID: $0, name: app.localizedName ?? $0)
                }
            }
        let selectedIDs = distractionBundleIDs.union(messagesBundleIDs)
        let ownBundleID = Bundle.main.bundleIdentifier

        Task.detached(priority: .utility) { [weak self] in
            var found = Self.scanApplicationFolders()
            for app in running where found[app.bundleID] == nil {
                found[app.bundleID] = app
            }
            for bundleID in selectedIDs where found[bundleID] == nil {
                found[bundleID] = DiscoveredApp(bundleID: bundleID, name: bundleID)
            }
            if let ownBundleID { found.removeValue(forKey: ownBundleID) }
            let sorted = found.values.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            await MainActor.run { self?.installedApps = sorted }
        }
    }

    private nonisolated static func scanApplicationFolders() -> [String: DiscoveredApp] {
        var found: [String: DiscoveredApp] = [:]
        let fileManager = FileManager.default
        let directories = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities"
        ]
        for directory in directories {
            guard let items = try? fileManager.contentsOfDirectory(atPath: directory) else {
                continue
            }
            for item in items where item.hasSuffix(".app") {
                let url = URL(fileURLWithPath: directory).appendingPathComponent(item)
                guard let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
                found[bundleID] = DiscoveredApp(
                    bundleID: bundleID,
                    name: (item as NSString).deletingPathExtension
                )
            }
        }
        return found
    }

    private func refreshLaunchAtLoginStatus() {
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }
}

extension MacModel: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
