# NoiseGate

**A personalized screen-time tracker for iPhone, iPad, and Mac — signal in,
noise out.**

Apple's Screen Time counts *everything*: the news you should read, the maps
that get you places, the FaceTime calls with your family. The number ends up
meaningless, so you ignore it. NoiseGate flips the model — you flag the apps
that are actually noise (the swiping, the feeds), and those are the only
thing it ever measures. Messages gets its own separate line. Everything else
on your devices is invisible to it.

And it **never blocks anything**. NoiseGate is observation only: budgets,
gauges, and factual threshold notifications. Blocking, if you want it,
belongs to a dedicated blocking app.

> **Contributing (humans or AI agents):** read [AGENTS.md](AGENTS.md) first —
> repo map, build steps, architecture invariants, and the design-system rules.
> The visual identity lives in `Shared/DesignSystem.swift`; all UI draws from
> those `NG.*` tokens.

## What it does

- **Tracks only what you flag.** Apps are chosen with Apple's
  `FamilyActivityPicker`; the selection is opaque tokens, so NoiseGate never
  even learns which apps you picked. NYT, FaceTime, WhatsApp, work apps —
  never counted, unless you say so.
- **Per-app toggles.** Every flagged app gets a switch: tracked or paused.
  Pause Hinge for a week without losing your list; flip it back on later.
- **Messages on its own line.** A separate budget and gauge for the Messages
  app, so thread time doesn't blur into feed time.
- **Threshold notifications, your choice of thresholds.** A notification at
  50%, 80%, and 100% of each budget, and at 150% / 200% if exceeded — each
  toggleable in settings, each fired at most once per day, at standard
  priority, with neutral, factual copy.
- **Today and 7-day views.** Exact daily totals and top apps for today, plus
  an exact 7-day bar chart per category (rendered inside Apple's
  privacy-preserving report extension) with the budget line drawn in.
- **History stats.** A rolling 30-day per-day record powers a "budget reached
  on N of the last 7 days" card on iOS and a 7-day mini chart in the Mac
  menu popover.
- **Menu-bar readout (Mac).** Optionally show today's noise minutes right in
  the menu bar.
- **Widgets everywhere.** Budget rings on the iPhone/iPad home screen and
  lock screen, and on the Mac desktop / Notification Center.
- **iPhone, iPad, and Mac.** One iOS app for iPhone and iPad; a menu-bar
  companion on the Mac (Apple offers no third-party Screen Time API there, so
  it does its own frontmost-app accounting, idle-aware).

## What's in the box

| Target | What it does |
| --- | --- |
| `NoiseGate` (iOS — iPhone **and iPad**) | Today gauges, per-app tracked/paused toggles, budgets |
| `NoiseGateMonitor` (iOS) | Background monitor: budget thresholds → gentle nudges, widget feed |
| `NoiseGateReport` (iOS) | Renders exact usage vs. budget inside the app (privacy-preserving) |
| `NoiseGateWidget` (iOS) | Home-screen + lock-screen budget rings |
| `NoiseGateMac` (macOS) | Menu-bar tracker: flagged apps only, same check-ins, sandboxed |
| `NoiseGateMacWidget` (macOS) | Desktop/Notification-Center widget |

## Building

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
xcodegen generate
open NoiseGate.xcodeproj
```

Before building:

1. **Team + identifiers.** In `project.yml`, set `DEVELOPMENT_TEAM` and replace
   the `com.example.noisegate` bundle-id prefix with your own. Update the app
   group (`group.com.example.noisegate`) in both `project.yml` and
   `Shared/AppGroup.swift` to match.
2. **Family Controls capability.** In your Apple Developer account, enable
   *Family Controls* for the iOS app, monitor, and report identifiers. It works
   out of the box on device for development; **App Store distribution requires
   Apple's approval** of the Family Controls & Personal Device Usage
   entitlement (apply via Apple's request form).
3. **Run on a real device.** Screen Time APIs are not functional in the iOS
   simulator.

First launch on iPhone: grant Screen Time access and notifications, flag your
noise apps and the Messages app in the *Noise* tab, set budgets in *Budgets*,
add the widget. Done.

## Design notes & honest limitations

- **iOS usage numbers come from Apple's privacy wall.** Exact durations can
  only be *rendered* by the sandboxed report extension (the *Today* tab) —
  they cannot be exported to the app or the widget. The widget therefore shows
  a **floor** based on crossed budget thresholds (10% steps), marked with `≥`.
  That's the best any third-party iOS widget can legally do.
- **Pausing an app** removes it from monitoring going forward; the day's
  already-crossed thresholds don't un-cross until the midnight reset.
- **You pick Messages yourself.** Apple doesn't let apps pre-select another
  app programmatically, so add Messages (and nothing else, ideally) in the
  picker under *Messages*. Leave FaceTime and WhatsApp out — that's the point.
- **The Mac does its own accounting**: frontmost app sampled every 5 seconds
  while you're active (input within 2 minutes), only flagged bundle ids
  counted. Both Mac targets are sandboxed.
- Each device keeps its own daily tally — iPhone, iPad, and Mac are separate
  counts, not a merged total.

## Repo layout

```
NoiseGate/
├── project.yml               # XcodeGen spec (all 6 targets, entitlements, plists)
├── AGENTS.md                 # Agent/contributor guide (start here)
├── Shared/                   # Cross-platform: config, snapshot, design system, gauge
├── iOS/
│   ├── App/                  # SwiftUI app (Today / Noise / Budgets)
│   ├── ScreenTimeShared/     # Selection + muted-token store (app + monitor)
│   ├── MonitorExtension/     # DeviceActivityMonitor: thresholds → nudges
│   ├── ReportExtension/      # DeviceActivityReport: exact usage rendering
│   └── Widget/               # WidgetKit widget
└── macOS/
    ├── App/                  # Menu-bar tracker + nudges
    └── Widget/               # macOS widget
```
