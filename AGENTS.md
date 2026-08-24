# AGENTS.md — working on NoiseGate

Guidance for AI coding agents (ChatGPT/Codex, Claude, Copilot, etc.) and new
contributors. Read this before touching anything.

## What this app is

NoiseGate is an in-your-face screen-time app for iPhone, iPad, and Mac. It
tracks ONLY two user-chosen categories — "noise" apps (distractions; budgeted,
nudged, and blocked) and messaging apps (tracked separately, nudged, **never
blocked**) — and ignores everything else on the device. The tone of the whole
product is loud and blunt: red slabs, condensed caps, "STOP.", "NOPE.",
"YOU'RE OVER." Do not soften the copy or the visuals; that is the product.

## Repo map

```
project.yml                     XcodeGen spec — SINGLE source of truth for all
                                7 targets, entitlements, and Info.plists
Shared/                         Compiled into EVERY target (both platforms).
  AppGroup.swift                App-group id + UserDefaults keys + day keys
  BudgetConfig.swift            User settings (budgets, quiet hours) + threshold constants
  UsageSnapshot.swift           Widget-facing daily summary (see "floor" below)
  DesignSystem.swift            NG tokens: colors, typography, HazardStripes, cards
  BudgetGauge.swift             The budget ring used by apps + widgets
iOS/
  App/                          SwiftUI app (custom tab shell: Today/Blocking/Budgets)
  ScreenTimeShared/             FamilyControls/ManagedSettings helpers — iOS app,
                                monitor, and shield targets ONLY (needs entitlement)
  MonitorExtension/             DeviceActivityMonitor: thresholds → nudges/shields
  ReportExtension/              DeviceActivityReport: renders exact usage (sandboxed)
  ShieldConfigExtension/        The red "STOP." block screen
  Widget/                       WidgetKit widget (home + lock screen)
macOS/
  App/                          Menu-bar app: tracker, nudges, enforcement, slam overlay
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
3. **Threshold events encode meaning in their names**: `"noise.p80"` =
   noise budget 80% crossed; `"msg.p150"` = messages 150%. Parsing lives in
   the monitor extension (`components(separatedBy: ".p")`). Percent lists come
   from `BudgetConfig.progressPercents` / `.overtimePercents`; keep the app's
   event registration (`ScreenTimeModel.restartMonitoring`) and the monitor's
   handling in sync if you change them.
4. **Shield state is a set of reasons** (`focus` / `budget` / `quiet`)
   persisted in app-group defaults; the shield stays up while the set is
   non-empty. Both the app and the monitor extension mutate it through
   `ShieldController` only. The `ManagedSettingsStore` name is `"noisegate"`.
5. **Messaging is never blocked.** Nudges yes, shields no. This is a product
   invariant, not an oversight.
6. **The Mac app is intentionally NOT sandboxed** (it hides other apps for
   enforcement, impossible from the sandbox) and has no Screen Time API — it
   samples the frontmost app every 5s while input is recent (<2 min idle) and
   counts only flagged bundle ids. The Mac **widget** IS sandboxed. Don't
   "fix" either.
7. **Day rollover** is keyed by `DayKey.today()` (local `yyyy-MM-dd`). On iOS
   the monitor's `intervalDidStart(daily)` resets the snapshot and lifts the
   budget shield; on Mac `rolloverIfNeeded()` does it. Both must keep working
   after any storage change.
8. Restarting monitoring (`stopMonitoring` + `startMonitoring`) resets
   DeviceActivity threshold accumulation mid-day — known Apple quirk. Don't
   add code that restarts monitoring more often than a real settings change.

## Design system (UI work)

- All colors/typography come from `Shared/DesignSystem.swift` (`NG.*` tokens,
  `Font.ngDisplay/ngNumber/ngLabel`). **No raw color or font literals in
  views.** Light/dark is handled inside the tokens.
- Visual language: warm paper ground, alarm red + deep red for the over/blocked
  world, orange = noise, teal = messages, indigo = focus. Condensed-black caps
  for display type ("STOP."), heavy rounded for numerals, tracked small caps
  for labels. `HazardStripes` marks over-budget surfaces. Cards via `.ngCard()`.
- Copy voice: second person, blunt, a little funny, short sentences with hard
  periods ("Put. It. Down."). Nudges escalate — never make them politer.
- Respect `prefers-reduced-motion` equivalents: gate repeat/looping animations
  where possible; haptics via `.sensoryFeedback` (iOS only).

## Conventions

- Swift 5.9, SwiftUI, iOS 17+ / macOS 14+, zero third-party dependencies —
  keep it that way unless explicitly asked.
- 4-space indent, `// MARK:` sections, doc comments explain *why* and
  platform constraints, not what the next line does.
- Commit messages: imperative summary line, body explains behavior changes.
  Do not commit `NoiseGate.xcodeproj`, `DerivedData`, or `.DS_Store`.
