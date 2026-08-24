import AppKit
import Combine
import CoreGraphics
import Foundation
import UserNotifications
import WidgetKit

/// Per-day usage ledger: seconds of frontmost time per bundle identifier.
/// Only bundle ids the user flagged are ever recorded.
struct MacLedger: Codable {
    var dayKey: String = DayKey.today()
    var seconds: [String: Double] = [:]

    static func loadToday() -> MacLedger {
        var ledger = AppGroup.defaults.codable(MacLedger.self, forKey: StoreKey.macLedger)
            ?? MacLedger()
        if ledger.dayKey != DayKey.today() {
            ledger = MacLedger()
        }
        return ledger
    }

    func save() {
        AppGroup.defaults.setCodable(self, forKey: StoreKey.macLedger)
    }
}

struct DiscoveredApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

/// Pure observation: samples the frontmost app while the Mac is in use,
/// counts only listed bundle ids, and posts factual budget notifications.
/// No blocking or hiding of any kind.
@MainActor
final class MacModel: ObservableObject {
    @Published var config = BudgetConfig.load() {
        didSet { config.save(); publishSnapshot() }
    }
    @Published var noiseBundleIDs: Set<String>
    @Published var messagesBundleIDs: Set<String>
    @Published var noiseSecondsToday: Double = 0
    @Published var messagesSecondsToday: Double = 0
    @Published var installedApps: [DiscoveredApp] = []

    private var ledger = MacLedger.loadToday()
    private var timer: Timer?
    private var ticksSincePersist = 0
    private let tickSeconds: Double = 5
    /// Stop counting after 2 minutes without keyboard/mouse input.
    private let idleCutoff: Double = 120

    var noiseMinutesToday: Int { Int(noiseSecondsToday / 60) }
    var messagesMinutesToday: Int { Int(messagesSecondsToday / 60) }

    init() {
        noiseBundleIDs = Set(AppGroup.defaults.stringArray(forKey: StoreKey.macNoiseApps) ?? [])
        // Just Apple Messages by default — FaceTime and WhatsApp are real
        // conversation, not noise, and stay untracked unless flagged.
        messagesBundleIDs = Set(
            AppGroup.defaults.stringArray(forKey: StoreKey.macMessagesApps)
                ?? ["com.apple.MobileSMS", "com.apple.iChat"]
        )
        recomputeTotals()
        requestNotificationPermission()
        discoverApps()
        startTicking()

        // The ledger normally persists once a minute; flush on quit so up to
        // 60s of tracked time isn't lost.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.ledger.save()
            }
        }
    }

    // MARK: - Selection persistence

    func toggleNoise(_ bundleID: String) {
        if noiseBundleIDs.contains(bundleID) {
            noiseBundleIDs.remove(bundleID)
        } else {
            noiseBundleIDs.insert(bundleID)
        }
        AppGroup.defaults.set(Array(noiseBundleIDs).sorted(), forKey: StoreKey.macNoiseApps)
        recomputeTotals()
        publishSnapshot()
    }

    func toggleMessages(_ bundleID: String) {
        if messagesBundleIDs.contains(bundleID) {
            messagesBundleIDs.remove(bundleID)
        } else {
            messagesBundleIDs.insert(bundleID)
        }
        AppGroup.defaults.set(Array(messagesBundleIDs).sorted(), forKey: StoreKey.macMessagesApps)
        recomputeTotals()
        publishSnapshot()
    }

    // MARK: - Tracking loop

    private func startTicking() {
        let timer = Timer(timeInterval: tickSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        rolloverIfNeeded()

        guard secondsSinceLastInput() < idleCutoff,
              let frontmost = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontmost.bundleIdentifier
        else { persistIfDue(); return }

        if noiseBundleIDs.contains(bundleID) || messagesBundleIDs.contains(bundleID) {
            ledger.seconds[bundleID, default: 0] += tickSeconds
            recomputeTotals()
            checkNudges()
        }
        persistIfDue()
    }

    private func rolloverIfNeeded() {
        guard ledger.dayKey != DayKey.today() else { return }
        // File the finished day into history before resetting.
        HistoryStore.record(DayRecord(
            dayKey: ledger.dayKey,
            noiseMinutes: noiseMinutesToday,
            messagesMinutes: messagesMinutesToday,
            noiseBudgetMinutes: config.noiseBudgetMinutes,
            messagesBudgetMinutes: config.messagesBudgetMinutes,
            isFloor: false
        ))
        ledger = MacLedger()
        ledger.save()
        AppGroup.defaults.set([String](), forKey: StoreKey.macNudgesSent)
        recomputeTotals()
        publishSnapshot()
    }

    /// The last 6 finished days plus today, oldest first — for the menu chart.
    var weekRecords: [DayRecord] {
        var records = HistoryStore.lastDays(6)
        records.append(DayRecord(
            dayKey: ledger.dayKey,
            noiseMinutes: noiseMinutesToday,
            messagesMinutes: messagesMinutesToday,
            noiseBudgetMinutes: config.noiseBudgetMinutes,
            messagesBudgetMinutes: config.messagesBudgetMinutes,
            isFloor: false
        ))
        return records
    }

    private func persistIfDue() {
        ticksSincePersist += 1
        if Double(ticksSincePersist) * tickSeconds >= 60 {
            ticksSincePersist = 0
            ledger.save()
            publishSnapshot()
        }
    }

    private func recomputeTotals() {
        noiseSecondsToday = ledger.seconds
            .filter { noiseBundleIDs.contains($0.key) }
            .values.reduce(0, +)
        messagesSecondsToday = ledger.seconds
            .filter { messagesBundleIDs.contains($0.key) }
            .values.reduce(0, +)
    }

    /// Minimum idle time across common input event types (safer than the
    /// undocumented "any input" event type).
    private func secondsSinceLastInput() -> Double {
        let types: [CGEventType] = [
            .keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown,
            .scrollWheel, .flagsChanged
        ]
        return types
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }

    // MARK: - Nudges (each sent at most once per day)

    private func checkNudges() {
        nudgeIfCrossed(kind: "noise", minutes: noiseMinutesToday,
                       budget: config.noiseBudgetMinutes)
        nudgeIfCrossed(kind: "msg", minutes: messagesMinutesToday,
                       budget: config.messagesBudgetMinutes)
    }

    private func nudgeIfCrossed(kind: String, minutes: Int, budget: Int) {
        guard budget > 0 else { return }
        let percents = BudgetConfig.nudgePercents + BudgetConfig.overtimePercents
        for pct in percents where minutes * 100 >= budget * pct {
            guard config.notifies(atPercent: pct),
                  let text = NudgeText.notification(kind: kind, percent: pct,
                                                    budgetMinutes: budget) else { continue }
            notifyOnce(id: "\(kind).\(pct)", title: text.title, body: text.body)
        }
    }

    /// Sends each distinct nudge at most once per day.
    private func notifyOnce(id: String, title: String, body: String) {
        let key = "\(id)@\(DayKey.today())"
        var sent = AppGroup.defaults.stringArray(forKey: StoreKey.macNudgesSent) ?? []
        guard !sent.contains(key) else { return }
        sent.append(key)
        AppGroup.defaults.set(sent, forKey: StoreKey.macNudgesSent)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "noisegate.\(key)", content: content, trigger: nil)
        )
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Widget feed

    private func publishSnapshot() {
        var snap = UsageSnapshot()
        snap.noiseMinutes = noiseMinutesToday
        snap.messagesMinutes = messagesMinutesToday
        snap.noiseBudgetMinutes = config.noiseBudgetMinutes
        snap.messagesBudgetMinutes = config.messagesBudgetMinutes
        snap.isFloor = false
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - App discovery (for the pickers)

    /// Reads running apps on the main actor (NSWorkspace is main-thread
    /// territory), then scans the Applications folders off the main thread —
    /// Bundle(url:) over a couple hundred apps is a visible hitch otherwise.
    func discoverApps() {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                app.bundleIdentifier.map {
                    DiscoveredApp(bundleID: $0, name: app.localizedName ?? $0)
                }
            }
        Task.detached(priority: .utility) { [weak self] in
            var found = Self.scanApplicationFolders()
            for app in running where found[app.bundleID] == nil {
                found[app.bundleID] = app
            }
            let sorted = found.values.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            await MainActor.run { self?.installedApps = sorted }
        }
    }

    private nonisolated static func scanApplicationFolders() -> [String: DiscoveredApp] {
        var found: [String: DiscoveredApp] = [:]
        let fm = FileManager.default
        let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities"]
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(item)
                if let bundleID = Bundle(url: url)?.bundleIdentifier {
                    found[bundleID] = DiscoveredApp(
                        bundleID: bundleID,
                        name: (item as NSString).deletingPathExtension
                    )
                }
            }
        }
        return found
    }
}
