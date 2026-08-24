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

@MainActor
final class MacModel: ObservableObject {
    @Published var config = BudgetConfig.load() {
        didSet { config.save(); publishSnapshot() }
    }
    @Published var noiseBundleIDs: Set<String>
    @Published var messagesBundleIDs: Set<String>
    @Published var focusOn = false
    @Published var noiseSecondsToday: Double = 0
    @Published var messagesSecondsToday: Double = 0
    @Published var installedApps: [DiscoveredApp] = []

    private var ledger = MacLedger.loadToday()
    private var timer: Timer?
    private var ticksSincePersist = 0
    private let tickSeconds: Double = 5
    /// Stop counting after 2 minutes without keyboard/mouse input.
    private let idleCutoff: Double = 120
    /// While you're actively over budget and unblocked, nag again this often.
    private let overtimeNagInterval: TimeInterval = 300
    private var lastNoiseOvertimeNag: Date?
    private var lastMessagesOvertimeNag: Date?

    var noiseMinutesToday: Int { Int(noiseSecondsToday / 60) }
    var messagesMinutesToday: Int { Int(messagesSecondsToday / 60) }

    var inQuietHours: Bool {
        guard config.quietHoursEnabled else { return false }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: .now)
        let now = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let start = config.quietStartMinutes, end = config.quietEndMinutes
        return start <= end ? (now >= start && now < end) : (now >= start || now < end)
    }

    var enforcementActive: Bool {
        focusOn
            || inQuietHours
            || (config.blockNoiseAtBudget && noiseMinutesToday >= config.noiseBudgetMinutes)
    }

    init() {
        noiseBundleIDs = Set(AppGroup.defaults.stringArray(forKey: StoreKey.macNoiseApps) ?? [])
        messagesBundleIDs = Set(
            AppGroup.defaults.stringArray(forKey: StoreKey.macMessagesApps)
                ?? ["com.apple.MobileSMS", "com.apple.iChat"]
        )
        recomputeTotals()
        requestNotificationPermission()
        discoverApps()
        startTicking()
        observeActivations()
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
    }

    func toggleMessages(_ bundleID: String) {
        if messagesBundleIDs.contains(bundleID) {
            messagesBundleIDs.remove(bundleID)
        } else {
            messagesBundleIDs.insert(bundleID)
        }
        AppGroup.defaults.set(Array(messagesBundleIDs).sorted(), forKey: StoreKey.macMessagesApps)
        recomputeTotals()
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

        let isNoise = noiseBundleIDs.contains(bundleID)
        let isMessages = messagesBundleIDs.contains(bundleID)

        if isNoise || isMessages {
            ledger.seconds[bundleID, default: 0] += tickSeconds
            recomputeTotals()
            checkNudges()
        }

        if isNoise && enforcementActive {
            block(frontmost)
        } else if isNoise && noiseMinutesToday >= config.noiseBudgetMinutes {
            // Over budget with blocking off: keep nagging every 5 minutes.
            nagOvertime(kind: "noise", lastNag: &lastNoiseOvertimeNag,
                        overMinutes: noiseMinutesToday - config.noiseBudgetMinutes)
        }
        if isMessages && messagesMinutesToday >= config.messagesBudgetMinutes {
            nagOvertime(kind: "msg", lastNag: &lastMessagesOvertimeNag,
                        overMinutes: messagesMinutesToday - config.messagesBudgetMinutes)
        }
        persistIfDue()
    }

    private func rolloverIfNeeded() {
        guard ledger.dayKey != DayKey.today() else { return }
        ledger = MacLedger()
        ledger.save()
        AppGroup.defaults.set([String](), forKey: StoreKey.macNudgesSent)
        recomputeTotals()
        publishSnapshot()
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

    // MARK: - Enforcement

    private func observeActivations() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleID = app.bundleIdentifier,
                      self.noiseBundleIDs.contains(bundleID),
                      self.enforcementActive
                else { return }
                self.block(app)
            }
        }
    }

    private func block(_ app: NSRunningApplication) {
        app.hide()
        let reason: String
        if focusOn { reason = "YOU turned Focus on. You meant it." }
        else if inQuietHours { reason = "It's quiet hours. Go to bed." }
        else { reason = "Today's noise budget is SPENT." }
        SlamOverlay.shared.slam(appName: app.localizedName ?? "That app", reason: reason)
        notifyOnce(id: "blocked.\(app.bundleIdentifier ?? "?")",
                   title: "⛔️ \(app.localizedName ?? "That app") is BLOCKED",
                   body: reason)
    }

    func setFocus(_ on: Bool) {
        focusOn = on
        publishSnapshot()
        if on, let frontmost = NSWorkspace.shared.frontmostApplication,
           let bundleID = frontmost.bundleIdentifier,
           noiseBundleIDs.contains(bundleID) {
            block(frontmost)
        }
    }

    // MARK: - Nudges

    private func checkNudges() {
        nudgeIfCrossed(kind: "noise", minutes: noiseMinutesToday,
                       budget: config.noiseBudgetMinutes)
        nudgeIfCrossed(kind: "msg", minutes: messagesMinutesToday,
                       budget: config.messagesBudgetMinutes)
    }

    private func nudgeIfCrossed(kind: String, minutes: Int, budget: Int) {
        guard budget > 0 else { return }
        for pct in BudgetConfig.nudgePercents where minutes * 100 >= budget * pct {
            let title: String
            let body: String
            var critical = false
            switch (kind, pct) {
            case ("noise", 50):
                title = "⚠️ HALF the noise budget — gone"
                body = "That's half of \(budget.asHoursMinutes) on apps you yourself called worthless."
            case ("noise", 80):
                title = "🚨 80% burned"
                body = "Wrap it up — \(max(0, budget - minutes).asHoursMinutes) of noise left. NOW."
                critical = true
            case ("noise", 100):
                title = "⛔️ Noise budget SPENT"
                body = config.blockNoiseAtBudget
                    ? "Noise apps get slammed shut for the rest of the day. Go be a person."
                    : "You're over budget and blocking is off. That was your call."
                critical = true
            case ("msg", 50):
                title = "💬 Messages: halfway"
                body = "Half of today's messaging budget used."
            case ("msg", 80):
                title = "💬 Messages at 80%"
                body = "You've been in messages a while. Just call them."
            case ("msg", 100):
                title = "💬 Messages budget SPENT"
                body = "Over \(budget.asHoursMinutes) of messaging today — tracked, never blocked."
                critical = true
            default:
                continue
            }
            notifyOnce(id: "\(kind).\(pct)", title: title, body: body, critical: critical)
        }
    }

    /// While you're actively in an over-budget category, keep the pressure on —
    /// one nag per `overtimeNagInterval`, not once per day.
    private func nagOvertime(kind: String, lastNag: inout Date?, overMinutes: Int) {
        if let last = lastNag, Date().timeIntervalSince(last) < overtimeNagInterval { return }
        lastNag = Date()
        if kind == "noise" {
            post(id: "noise.overtime.\(Int(Date().timeIntervalSince1970))",
                 title: "⛔️ STILL in the noise",
                 body: overMinutes > 0
                    ? "\(overMinutes.asHoursMinutes) past your noise budget and counting. Close it."
                    : "Your noise budget is spent and you're still here. Close it.",
                 critical: true)
        } else {
            post(id: "msg.overtime.\(Int(Date().timeIntervalSince1970))",
                 title: "💬 Still in messages",
                 body: overMinutes > 0
                    ? "\(overMinutes.asHoursMinutes) over your messaging budget. Wrap it up or just call."
                    : "Messaging budget spent. Wrap it up or just call.",
                 critical: true)
        }
    }

    /// Sends each distinct nudge at most once per day.
    private func notifyOnce(id: String, title: String, body: String, critical: Bool = false) {
        let key = "\(id)@\(DayKey.today())"
        var sent = AppGroup.defaults.stringArray(forKey: StoreKey.macNudgesSent) ?? []
        guard !sent.contains(key) else { return }
        sent.append(key)
        AppGroup.defaults.set(sent, forKey: StoreKey.macNudgesSent)
        post(id: key, title: title, body: body, critical: critical)
    }

    private func post(id: String, title: String, body: String, critical: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = critical ? .timeSensitive : .active
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "noisegate.\(id)", content: content, trigger: nil)
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
        snap.focusActive = focusOn
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - App discovery (for the pickers)

    func discoverApps() {
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
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular {
            if let bundleID = app.bundleIdentifier, found[bundleID] == nil {
                found[bundleID] = DiscoveredApp(
                    bundleID: bundleID,
                    name: app.localizedName ?? bundleID
                )
            }
        }
        installedApps = found.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
