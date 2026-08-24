# AGENTS.md — working on NoiseGate

Guidance for AI coding agents (ChatGPT/Codex, Claude, Copilot, etc.) and new
contributors. Read this before touching anything.

## What this app is

NoiseGate is a personalized screen-time tracker for iPhone, iPad, and Mac. It
watches ONLY two user-chosen lists — "noise" apps (the distracting ones:
dating apps, feeds) and Messages — and is blind to everything else on the
device (news, maps, FaceTime, WhatsApp, work apps). Each flagged app has a
per-app toggle: tracked or paused, without losing the list.

**NoiseGate never blocks anything.** The user has a separate blocking app;
this one is observation only — budgets, gauges, and threshold notifications.
Do not add shields, enforcement, hiding of apps, or blocking of any kind.
That is a product decision, not a missing feature.

**Tone is neutral and factual.** All user-facing copy states numbers and
facts, nothing more ("Noise: 80% of budget used. About 9m remaining today.").
No praise, no scolding, no jokes, no exclamation points, no time-sensitive/
critical interruption levels. All notification copy lives in
`Shared/NudgeText.swift` — both platforms use it; edit copy there only.

## Repo map

```
project.yml                     XcodeGen spec — SINGLE source of truth for all
                                6 targets, entitlements, and Info.plists
Shared/                         Compiled into EVERY target (both platforms).
  AppGroup.swift                App-group id + UserDefaults keys + day keys
  BudgetConfig.swift            Budgets, notification prefs + threshold constants
  NudgeText.swift               ALL notification copy (both platforms)
  UsageSnapshot.swift           Widget-facing daily summary (see "floor" below)
  HistoryStore.swift            Rolling 30-day DayRecord history (per device)
  DesignSystem.swift            NG tokens: colors, typography, cards, stripes
  BudgetGauge.swift             The budget ring used by apps + widgets
iOS/
  App/                          SwiftUI app (custom tab shell: Today/Noise/Budgets)
  ScreenTimeShared/             FamilyControls selection + muted-token store —
                                iOS app and monitor targets ONLY (needs entitlement)
  MonitorExtension/             DeviceActivityMonitor: thresholds → gentle nudges
  ReportExtension/              DeviceActivityReport: renders exact usage (sandboxed)
  Widget/                       WidgetKit widget (home + lock screen)
macOS/
  App/                          Menu-bar app: frontmost-app tracker + nudges
  Widget/                       macOS widget
```

## Build & validate

- The Xcode project is **generated**: `brew install xcodegen && xcodegen generate`,
  then build the `NoiseGate` (iOS) and `NoiseGateMac` schemes.
- `NoiseGate.xcodeproj` is gitignored. **Never hand-edit or commit it**; change
  `project.yml` and regenerate. Target membership = the `sources` lists there.
- No unit tests yet. Validation = both schemes compile + manual run. Screen
  Time behavior **cannot** be exercised in the iOS simulator or CI; it needs a
  real device with the Family Controls capability.
- Placeholders that must stay in sync: bundle prefix `com.example.noisegate`
  and team `YOURTEAMID` in `project.yml`; app group `group.com.example.noisegate`
  in BOTH `project.yml` (all targets) and `Shared/AppGroup.swift`.

## Architecture rules (things that will break subtly if ignored)

1. **`Shared/` compiles everywhere** — Foundation + SwiftUI only. No
   FamilyControls/ManagedSettings/DeviceActivity/AppKit-only imports there;
   the widget targets have no Family Controls entitlement. iOS Screen Time
   code goes in `iOS/ScreenTimeShared/`.
2. **Data flow on iOS is one-way and privacy-bounded.** Exact usage numbers
   exist only inside the Report extension's view (Apple's privacy wall — they
   cannot be exported to the app, the widget, or a server). The widget shows a
   **floor**: the monitor extension writes `UsageSnapshot` minutes equal to the
   highest crossed threshold (10% steps of the budget). Fields are labeled
   `isFloor` and rendered with "≥". Never present floor values as exact.
3. **Muted tokens = paused, not deleted.** `SelectionStore` keeps each
   selection plus a `MutedTokens` set. Monitoring events and report filters are
   built from the *active* sets (`ScreenTimeModel.activeNoiseApps` etc.), so a
   paused app is invisible to tracking. `applyChanges()` prunes muted tokens
   no longer in the selection. The tokens are opaque; UI renders them with
   `Label(token)`, which shows the real name/icon via the system.
4. **Threshold events encode meaning in their names**: `"noise.p80"` =
   noise budget 80% crossed; `"msg.p150"` = messages 150%. Parsing lives in
   the monitor extension (`components(separatedBy: ".p")`). Percent lists come
   from `BudgetConfig.progressPercents` / `.overtimePercents`; keep the app's
   event registration (`ScreenTimeModel.restartMonitoring`) and the monitor's
   handling in sync if you change them.
5. **The Mac app has no Screen Time API** — it samples the frontmost app every
   5s while input is recent (<2 min idle) and counts only flagged bundle ids.
   Both Mac targets are sandboxed. Default messaging bundle ids are Apple
   Messages only (`com.apple.MobileSMS` / `com.apple.iChat`) — FaceTime and
   WhatsApp deliberately untracked unless the user flags them.
6. **Day rollover** is keyed by `DayKey.today()` (local `yyyy-MM-dd`). On iOS
   the monitor's `intervalDidStart(daily)` resets the snapshot; on Mac
   `rolloverIfNeeded()` does it. Both file the finished day into
   `HistoryStore` *before* resetting (iOS reads the raw stored snapshot, not
   `loadToday()`, which would already have reset it). CRITICAL:
   `intervalDidStart` ALSO fires on every mid-day monitoring restart (any
   settings/toggle change) — it must return early when the stored snapshot's
   dayKey is already today, or it wipes the day's floor and nudge ledger.
6b. **Report contexts are string-matched** between the host views and the
   report extension: "Noise", "Messages", "Noise Week", "Messages Week".
   The week scenes render exact 7-day Swift Charts inside the privacy
   sandbox; the host switches context + filter interval via the Today/7 Days
   range picker. Keep both sides' context strings identical.
6c. **Notification preferences** live in `BudgetConfig` (`notifyAt`,
   `overtimeNotifications`) and are checked via `config.notifies(atPercent:)`
   in BOTH the iOS monitor and the Mac tracker. `BudgetConfig` decodes with
   `decodeIfPresent` fallbacks so newly added fields never wipe stored
   budgets — keep that pattern when adding fields.
7. Restarting monitoring (`stopMonitoring` + `startMonitoring`) resets
   DeviceActivity threshold accumulation mid-day — known Apple quirk. That's
   why `ScreenTimeModel.applyChanges()` persists immediately but defers the
   expensive side effects (`syncDeferred()`: snapshot write + widget reload +
   restart) behind a 0.8s debounce, so rapid stepper taps or toggle flips
   coalesce into one sync. Don't add undebounced restart/reload paths.
   DeviceActivityReport filters must also stay value-stable across renders
   (day-boundary interval ends, never `.now`) or the report re-queries on
   every SwiftUI body evaluation.
8. Notifications fire at most once per day per milestone, enforced by
   sent-key ledgers (`iosNudgesSent` / `macNudgesSent`), which also covers
   thresholds re-firing after a mid-day monitoring restart. The daily reset
   clears both. Keep that dedupe when touching notification code.

## Design system (UI work)

- All colors/typography come from `Shared/DesignSystem.swift` (`NG.*` tokens,
  `Font.ngDisplay/ngNumber/ngLabel`). **No raw color or font literals in
  views.** Light/dark is handled inside the tokens.
- Visual language: warm paper ground; orange = noise, teal = messages; alarm
  red appears only as an accent for the over-budget state. Condensed-black
  caps for display type, heavy rounded for numerals, tracked small caps for
  labels, `.ngCard()` surfaces.
- Copy voice: neutral and factual everywhere (see the tone rule at the top).
  State what is tracked, the numbers, and that nothing is blocked.

## Conventions

- Swift 5.9, SwiftUI, iOS 17+ / macOS 14+, zero third-party dependencies —
  keep it that way unless explicitly asked.
- 4-space indent, `// MARK:` sections, doc comments explain *why* and
  platform constraints, not what the next line does.
- Commit messages: imperative summary line, body explains behavior changes.
  Do not commit `NoiseGate.xcodeproj`, `DerivedData`, or `.DS_Store`.
