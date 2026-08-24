import Foundation
import SwiftUI
import FamilyControls
import DeviceActivity
import ManagedSettings
import UserNotifications
import WidgetKit

extension DeviceActivityName {
    /// All-day monitoring window carrying the budget threshold events.
    static let daily = Self("daily")
    /// Scheduled quiet-hours window during which noise apps are shielded.
    static let quietHours = Self("quietHours")
}

/// Event names encode category + percent so the monitor extension can decode
/// them without extra state: "noise.p80" = noise budget reached 80%.
enum ThresholdEvent {
    static func name(kind: String, percent: Int) -> DeviceActivityEvent.Name {
        DeviceActivityEvent.Name("\(kind).p\(percent)")
    }

    static func parse(_ name: DeviceActivityEvent.Name) -> (kind: String, percent: Int)? {
        let parts = name.rawValue.components(separatedBy: ".p")
        guard parts.count == 2, let pct = Int(parts[1]) else { return nil }
        return (parts[0], pct)
    }
}

@MainActor
final class ScreenTimeModel: ObservableObject {
    @Published var noiseSelection: FamilyActivitySelection = SelectionStore.noise()
    @Published var messagesSelection: FamilyActivitySelection = SelectionStore.messages()
    @Published var config: BudgetConfig = BudgetConfig.load()
    @Published var isAuthorized: Bool = AuthorizationCenter.shared.authorizationStatus == .approved
    @Published var focusOn: Bool = ShieldController.activeReasons().contains(.focus)
    @Published var lastError: String?

    private let center = DeviceActivityCenter()

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

    // MARK: - Focus

    func toggleFocus() {
        focusOn.toggle()
        if focusOn {
            ShieldController.add(.focus)
        } else {
            ShieldController.remove(.focus)
        }
        var snap = UsageSnapshot.loadToday()
        snap.focusActive = focusOn
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Persist + (re)schedule

    /// Saves selections and config, refreshes the shield to cover the current
    /// noise selection, and restarts DeviceActivity monitoring with fresh
    /// threshold events. Call after any selection or budget change.
    func applyChanges() {
        SelectionStore.saveNoise(noiseSelection)
        SelectionStore.saveMessages(messagesSelection)
        config.save()
        ShieldController.refresh()

        var snap = UsageSnapshot.loadToday()
        snap.noiseBudgetMinutes = config.noiseBudgetMinutes
        snap.messagesBudgetMinutes = config.messagesBudgetMinutes
        snap.isFloor = true
        snap.focusActive = focusOn
        snap.save()
        WidgetCenter.shared.reloadAllTimelines()

        guard isAuthorized else { return }
        restartMonitoring()
    }

    private func restartMonitoring() {
        center.stopMonitoring()

        // 1. All-day window with threshold events at every 10% of each budget.
        //    The 10% steps double as widget progress; 50/80/100 also nudge.
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        if !noiseSelection.isEmpty {
            for pct in BudgetConfig.progressPercents {
                events[ThresholdEvent.name(kind: "noise", percent: pct)] = DeviceActivityEvent(
                    applications: noiseSelection.applicationTokens,
                    categories: noiseSelection.categoryTokens,
                    webDomains: noiseSelection.webDomainTokens,
                    threshold: DateComponents(minute: max(1, config.noiseBudgetMinutes * pct / 100))
                )
            }
        }
        if !messagesSelection.isEmpty {
            for pct in BudgetConfig.progressPercents {
                events[ThresholdEvent.name(kind: "msg", percent: pct)] = DeviceActivityEvent(
                    applications: messagesSelection.applicationTokens,
                    categories: messagesSelection.categoryTokens,
                    webDomains: messagesSelection.webDomainTokens,
                    threshold: DateComponents(minute: max(1, config.messagesBudgetMinutes * pct / 100))
                )
            }
        }

        let allDay = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        do {
            if !events.isEmpty {
                try center.startMonitoring(.daily, during: allDay, events: events)
            }
        } catch {
            lastError = "Could not start daily monitoring: \(error.localizedDescription)"
        }

        // 2. Quiet hours window (shield applied in the monitor extension).
        if config.quietHoursEnabled, !noiseSelection.isEmpty {
            let quiet = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: config.quietStartMinutes / 60,
                                              minute: config.quietStartMinutes % 60),
                intervalEnd: DateComponents(hour: config.quietEndMinutes / 60,
                                            minute: config.quietEndMinutes % 60),
                repeats: true
            )
            do {
                try center.startMonitoring(.quietHours, during: quiet, events: [:])
            } catch {
                lastError = "Could not schedule quiet hours: \(error.localizedDescription)"
            }
        } else {
            ShieldController.remove(.quiet)
        }
    }
}

extension FamilyActivitySelection {
    var isEmpty: Bool {
        applicationTokens.isEmpty && categoryTokens.isEmpty && webDomainTokens.isEmpty
    }

    var summary: String {
        var parts: [String] = []
        if !applicationTokens.isEmpty { parts.append("\(applicationTokens.count) apps") }
        if !categoryTokens.isEmpty { parts.append("\(categoryTokens.count) categories") }
        if !webDomainTokens.isEmpty { parts.append("\(webDomainTokens.count) websites") }
        return parts.isEmpty ? "Nothing selected" : parts.joined(separator: ", ")
    }
}
