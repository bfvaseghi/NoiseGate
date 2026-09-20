import SwiftUI
import UIKit
import WidgetKit

/// What Tests/WidgetPreview renders: the iPhone widget's entry view at every
/// family it supports, driven by fixed data so two runs of the job produce
/// the same pixels. Every iPhone value is a lower bound, as on a real iPhone,
/// so the pictures carry the `≥` wording the product ships. The Mac scenes
/// draw the same Shared layouts with exact values so the Mac strings can be
/// reviewed too; Mac has no Lock Screen families, and those frames say so.
///
/// The harness renders every scene light and dark, so no scene needs a dark
/// variant of its own. It cannot render the tinted (`accented`) Home Screen
/// mode: the rendering mode is set by WidgetKit, not the environment.
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
        // ≥36m of 45m and ≥20m of 1h: "At least 80% of budget", "3 days
        // without a crossing" (the 45 four days back stops the walk), the
        // "1:42 PM" stamp beside the ledger name, strip "1 confirmed
        // crossing" with a paper dot on the crossed day.
        scene("typical-weekday", Fixture.entry(
            Fixture.snapshot(distractions: 36, messages: 20)
        )),
        // Exactly the budget: red ring, "Budget crossed", "Resets at
        // midnight", flag glyph.
        scene("budget-crossed", Fixture.entry(
            Fixture.snapshot(distractions: 45, messages: 20)
        )),
        // The 150% threshold: "At least 23m over budget"; small "≥23m over".
        scene("over-budget", Fixture.entry(
            Fixture.snapshot(distractions: 68, messages: 20)
        )),
        // Selected and running, no Distractions threshold fired yet today:
        // dashed ring, "—", "No checkpoint yet", clock hidden.
        scene("no-checkpoint-yet", Fixture.entry(
            Fixture.snapshot(distractions: 0, messages: 20, updatedAt: Fixture.startOfToday)
        )),
        // Fresh install: nothing selected, nothing running, no history;
        // "—", "Choose distracting apps" / "Choose apps".
        scene("no-apps-selected", Fixture.entry(
            Fixture.snapshot(distractions: nil, messages: nil, active: false),
            history: []
        )),
        // The monitor is stopped: ring still amber (the floor is still true),
        // "Tracking paused" led by the pause glyph, "1:42 PM" stamp kept.
        scene("tracking-paused", Fixture.entry(
            Fixture.snapshot(distractions: 36, messages: 20, active: false)
        )),
        // The Messages focus: teal ring, "MESSAGES", Distractions as the
        // secondary row.
        scene("messages-focus", Fixture.entry(
            Fixture.snapshot(distractions: 36, messages: 20),
            focus: .messages
        )),
        // The widest strings: "≥7h 45m" of "8h 00m", Messages over at
        // "≥1h 05m / 1h 00m". Numerals scale but stay above 13.3 pt;
        // "OF 8h 00m" fits at 11 pt; the Messages row drops to its 11 pt
        // floor rather than an ellipsis; the inline line is
        // "Distractions ≥7h 45m"; nothing clips.
        scene("long-values", Fixture.entry(
            Fixture.snapshot(
                distractions: 465,
                messages: 65,
                distractionBudget: 480,
                messagesBudget: 60
            )
        )),
        // The same values with the Messages focus: "≥7h 45m / 8h 00m" does
        // not fit beside "Distractions" at any legible size, so the row shows
        // the value alone; the inline line is "Messages ≥1h 05m".
        scene("long-values-messages-focus", Fixture.entry(
            Fixture.snapshot(
                distractions: 465,
                messages: 65,
                distractionBudget: 480,
                messagesBudget: 60
            ),
            focus: .messages
        )),
        // Yesterday reached its budget: "Crossed yesterday".
        scene("crossed-yesterday", Fixture.entry(
            Fixture.snapshot(distractions: 10, messages: 20),
            history: Fixture.history([18, 32, 20, 22, 30, 51])
        )),
        // Records for −6…−3 only: the streak line is omitted and the strip
        // shows two dashed outlines before today.
        scene("gap-in-history", Fixture.entry(
            Fixture.snapshot(distractions: 10, messages: 20),
            history: Fixture.history([18, 32, 45, 22], endingDaysAgo: 3)
        )),
        // After midnight, before the first monitor callback: zero minutes
        // with yesterday's write time. "—", "No checkpoint yet", no stamp,
        // masthead right hidden; the Messages row says "No checkpoint yet"
        // in running text, the inline line "Distractions — / 45m".
        scene("after-midnight", Fixture.entry(
            Fixture.snapshot(distractions: 0, messages: 0, updatedAt: Fixture.lateYesterday)
        )),
        // A Saturday with the weekend target: "OF 1h 15m".
        scene("weekend-budget", Fixture.entry(
            Fixture.snapshot(distractions: 40, messages: 20, distractionBudget: 75, now: Fixture.saturday),
            history: Fixture.history(now: Fixture.saturday)
        ), now: Fixture.saturday),
        // The ember accent beside the alarm red: distinguishable by glyph
        // and words, never by hue alone.
        scene("ember-accent-typical", Fixture.entry(
            Fixture.snapshot(distractions: 36, messages: 20)
        ), accent: .ember),
        scene("ember-accent-crossed", Fixture.entry(
            Fixture.snapshot(distractions: 45, messages: 20)
        ), accent: .ember),
        // The same layout on an iPad: the footer names the device.
        scene("ipad-typical", Fixture.entry(
            Fixture.snapshot(distractions: 36, messages: 20)
        ), device: "iPad"),
        // The Mac widget's families with exact values: "80% of budget",
        // "3 days under budget", "Tracking on this Mac", "THIS MAC · LIVE".
        macScene("mac-live", Fixture.macSnapshot(distractions: 36, messages: 20, active: true)),
        // The tracker stopped heartbeating at 1:42 PM: "Paused on this Mac ·
        // 1:42 PM", "THIS MAC · PAUSED 1:42 PM".
        macScene("mac-paused", Fixture.macSnapshot(distractions: 36, messages: 20, active: false)),
        // An exact zero is honest on the Mac: "0m", "0% of budget".
        macScene("mac-midnight-zero", Fixture.macSnapshot(distractions: 0, messages: 0, active: true))
    ]

    private static func scene(
        _ name: String,
        _ entry: SnapshotEntry,
        now: Date = Fixture.now,
        device: String = "iPhone",
        accent: AccentTheme = .amber
    ) -> (name: String, view: (WidgetFamily) -> AnyView) {
        (name, { family in
            // The Distractions accent is read from the app-group defaults
            // while rendering, so every scene selects its own: the order
            // scenes render in must not leak one scene's accent into the next.
            AccentTheme.select(accent)
            return AnyView(NoiseGateWidgetView(
                entry: entry,
                family: family,
                now: now,
                device: device
            ))
        })
    }

    private static func macScene(
        _ name: String,
        _ snapshot: UsageSnapshot,
        history: [DayRecord] = Fixture.history(isFloor: false)
    ) -> (name: String, view: (WidgetFamily) -> AnyView) {
        (name, { family in
            AccentTheme.select(.amber)
            let content = WidgetSystemContent(
                snapshot: snapshot,
                history: history,
                primaryLedger: .distractions,
                secondaryLedger: .messages,
                accuracy: .exact,
                device: "Mac",
                now: Fixture.now,
                calendar: Fixture.calendar
            )
            return AnyView(MacFamilyPreview(family: family, content: content))
        })
    }
}

/// The Mac widget's three families through the Shared layouts, as
/// `MacWidgetView` draws them. The renderer asks for every family in the
/// catalog, and the Mac has no Lock Screen; those frames carry a note rather
/// than an empty plate that could pass for a failed render.
private struct MacFamilyPreview: View {
    let family: WidgetFamily
    let content: WidgetSystemContent

    var body: some View {
        switch family {
        case .systemSmall:
            SmallSignalLayout(content: content)
        case .systemMedium:
            MediumSignalLayout(content: content)
        case .systemLarge:
            LargeSignalLayout(content: content)
        default:
            Text("Not a Mac family")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NG.inkSoft)
        }
    }
}

// MARK: - Fixed data

private enum Fixture {
    static let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .autoupdatingCurrent
        return value
    }()

    /// Wednesday 11 March 2026 at 14:00, local time. Local rather than UTC
    /// because the widget keys its days by the device calendar, and
    /// mid-afternoon keeps every derived day clear of a boundary.
    static let now: Date = calendar.date(
        from: DateComponents(year: 2026, month: 3, day: 11, hour: 14)
    ) ?? Date(timeIntervalSince1970: 1_773_237_600)

    /// Saturday 14 March 2026 at 14:00, for the weekend budget.
    static let saturday: Date = calendar.date(
        from: DateComponents(year: 2026, month: 3, day: 14, hour: 14)
    ) ?? now

    static let startOfToday: Date = calendar.startOfDay(for: now)

    static let lateYesterday: Date = calendar.date(
        from: DateComponents(year: 2026, month: 3, day: 10, hour: 23, minute: 10)
    ) ?? now

    /// Every snapshot was written at 13:42 on its own day unless a scene
    /// says otherwise.
    static func writeTime(on day: Date) -> Date {
        calendar.date(bySettingHour: 13, minute: 42, second: 0, of: day) ?? day
    }

    /// Finished days, listed oldest first, the last one `endingDaysAgo`
    /// days before `now`. The default is the brief's typical week: a
    /// confirmed crossing four days back, then three clear days.
    static func history(
        _ distractions: [Int] = [18, 32, 45, 22, 30, 29],
        endingDaysAgo: Int = 1,
        now: Date = now,
        isFloor: Bool = true
    ) -> [DayRecord] {
        distractions.enumerated().compactMap { index, minutes in
            let daysAgo = endingDaysAgo + distractions.count - 1 - index
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) else {
                return nil
            }
            return DayRecord(
                dayKey: DayKey.today(date),
                distractionMinutes: minutes,
                messagesMinutes: max(8, minutes / 2),
                distractionBudgetMinutes: 45,
                messagesBudgetMinutes: 60,
                isFloor: isFloor
            )
        }
    }

    /// `nil` minutes means the ledger has no selection.
    static func snapshot(
        distractions: Int?,
        messages: Int?,
        distractionBudget: Int = 45,
        messagesBudget: Int = 60,
        active: Bool = true,
        now: Date = now,
        updatedAt: Date? = nil,
        isFloor: Bool = true
    ) -> UsageSnapshot {
        UsageSnapshot(
            dayKey: DayKey.today(now),
            distractionMinutes: distractions ?? 0,
            messagesMinutes: messages ?? 0,
            distractionBudgetMinutes: distractionBudget,
            messagesBudgetMinutes: messagesBudget,
            distractionsConfigured: distractions != nil,
            messagesConfigured: messages != nil,
            isFloor: isFloor,
            monitoringIsActive: active,
            updatedAt: updatedAt ?? writeTime(on: now)
        )
    }

    /// The Mac tracker's snapshot: exact minutes, heartbeat at 13:42.
    static func macSnapshot(
        distractions: Int,
        messages: Int,
        active: Bool
    ) -> UsageSnapshot {
        snapshot(
            distractions: distractions,
            messages: messages,
            active: active,
            isFloor: false
        )
    }

    static func entry(
        _ snapshot: UsageSnapshot,
        history: [DayRecord] = history(),
        focus: NoiseGateWidgetFocus = .automatic
    ) -> SnapshotEntry {
        SnapshotEntry(date: now, snapshot: snapshot, history: history, focus: focus)
    }
}
