import SwiftUI
import UIKit
import WidgetKit

/// What Tests/WidgetPreview renders: the iPhone widget's entry view at every
/// family it supports, driven by fixed data so two runs of the job produce
/// the same pixels. Every value is a lower bound, as on a real iPhone, so
/// the pictures carry the `≥` wording the product ships. The Mac widget
/// draws the same Shared layouts with exact values and is not rendered here.
enum WidgetPreviewCatalog {
    static let app = "noisegate"

    static let families: [WidgetFamily] = [
        .systemSmall,
        .systemMedium,
        .systemLarge,
        .accessoryCircular,
        .accessoryRectangular,
        .accessoryInline
    ]

    /// The widget keeps WidgetKit's default margins (it never calls
    /// `contentMarginsDisabled()`), which are 16pt on the Home Screen. The
    /// Lock Screen families fill the frame's plate, which already stands in
    /// for the system's vibrant treatment.
    static func contentMargins(for family: WidgetFamily) -> EdgeInsets {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return EdgeInsets()
        default:
            return EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        }
    }

    /// `NG.paper`, the colour the widget passes to `containerBackground`,
    /// resolved for the requested appearance rather than left to whatever
    /// trait collection the renderer happens to run under.
    static func background(dark: Bool) -> Color {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        return Color(uiColor: UIColor(NG.paper).resolvedColor(with: traits))
    }

    // MARK: - Scenes

    static let scenes: [(name: String, view: (WidgetFamily) -> AnyView)] = [
        // Distractions 30% through, Messages 30% through: an ordinary day.
        scene("normal-day", Fixture.entry(
            Fixture.snapshot(distractions: 14, messages: 20)
        )),
        // 60% and 50%: the watch band, still in the ledger colours.
        scene("watch", Fixture.entry(
            Fixture.snapshot(distractions: 27, messages: 33)
        )),
        // 80% on both: the high band, the widget's own placeholder numbers.
        scene("high", Fixture.entry(
            Fixture.snapshot(distractions: 36, messages: 48)
        )),
        // Exactly the budget: "Budget crossed", the ring turns to alarm.
        scene("reached", Fixture.entry(
            Fixture.snapshot(distractions: 45, messages: 30)
        )),
        // Past the budget: "At least 23m over budget".
        scene("over-budget", Fixture.entry(
            Fixture.snapshot(distractions: 68, messages: 30)
        )),
        // Fresh install: nothing selected, nothing running, no history.
        scene("no-data", Fixture.entry(
            Fixture.snapshot(distractions: nil, messages: nil, active: false),
            history: []
        )),
        // Selected and running, but no threshold has fired yet today.
        scene("no-checkpoint", Fixture.entry(
            Fixture.snapshot(distractions: 0, messages: 0)
        )),
        // Stale: the monitor is not running, so the floors stop moving.
        scene("paused", Fixture.entry(
            Fixture.snapshot(distractions: 36, messages: 20, active: false)
        )),
        // Only Distractions selected; the Messages column asks for apps.
        scene("distractions-only", Fixture.entry(
            Fixture.snapshot(distractions: 27, messages: nil)
        )),
        // The Messages focus: a single ledger, teal, no secondary row.
        scene("messages-focus", Fixture.entry(
            Fixture.snapshot(distractions: 14, messages: 48),
            focus: .messages
        )),
        // Wide values ("≥7h 45m" of "8h") to exercise every scale guard.
        scene("long-values", Fixture.entry(
            Fixture.snapshot(
                distractions: 465,
                messages: 125,
                distractionBudget: 480,
                messagesBudget: 120
            )
        ))
    ]

    private static func scene(
        _ name: String,
        _ entry: SnapshotEntry
    ) -> (name: String, view: (WidgetFamily) -> AnyView) {
        (name, { family in
            AnyView(NoiseGateWidgetView(entry: entry, family: family, now: Fixture.now))
        })
    }
}

// MARK: - Fixed data

private enum Fixture {
    /// Wednesday 11 March 2026 at midday, local time. Local rather than UTC
    /// because the widget keys its days by the device calendar, and midday
    /// keeps every derived day clear of a boundary.
    static let now: Date = calendar.date(
        from: DateComponents(year: 2026, month: 3, day: 11, hour: 12)
    ) ?? Date(timeIntervalSince1970: 1_773_230_400)

    static let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .autoupdatingCurrent
        return value
    }()

    /// One of each day state the strip can draw, oldest first: a confirmed
    /// crossing, a checkpoint, a day with no record at all (the 8th is
    /// skipped), a day with no checkpoint, another checkpoint, and an
    /// overage. Today comes from the snapshot.
    static let history: [DayRecord] = [
        (offset: -6, distractions: 45, messages: 30),
        (offset: -5, distractions: 27, messages: 12),
        (offset: -3, distractions: 0, messages: 0),
        (offset: -2, distractions: 36, messages: 18),
        (offset: -1, distractions: 68, messages: 24)
    ].compactMap { day in
        guard let date = calendar.date(byAdding: .day, value: day.offset, to: now) else {
            return nil
        }
        return DayRecord(
            dayKey: DayKey.today(date),
            distractionMinutes: day.distractions,
            messagesMinutes: day.messages,
            distractionBudgetMinutes: 45,
            messagesBudgetMinutes: 60,
            isFloor: true
        )
    }

    /// `nil` minutes means the ledger has no selection.
    static func snapshot(
        distractions: Int?,
        messages: Int?,
        distractionBudget: Int = 45,
        messagesBudget: Int = 60,
        active: Bool = true
    ) -> UsageSnapshot {
        UsageSnapshot(
            dayKey: DayKey.today(now),
            distractionMinutes: distractions ?? 0,
            messagesMinutes: messages ?? 0,
            distractionBudgetMinutes: distractionBudget,
            messagesBudgetMinutes: messagesBudget,
            distractionsConfigured: distractions != nil,
            messagesConfigured: messages != nil,
            isFloor: true,
            monitoringIsActive: active,
            updatedAt: now
        )
    }

    static func entry(
        _ snapshot: UsageSnapshot,
        history: [DayRecord] = history,
        focus: NoiseGateWidgetFocus = .automatic
    ) -> SnapshotEntry {
        SnapshotEntry(date: now, snapshot: snapshot, history: history, focus: focus)
    }
}
