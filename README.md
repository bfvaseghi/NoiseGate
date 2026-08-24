# NoiseGate

**Screen time that gets in your face.** For iPhone, iPad, and Mac.

Apple's Screen Time counts *everything* — including the apps you're supposed to
be using — and then whispers about it. NoiseGate does the opposite: it only
cares about two things, and it is not subtle about either of them:

1. **Noise** — the apps you flag as pure distraction (social media and friends).
   Budgeted, nudged, and **blocked** when you're over.
2. **Messages** — tracked **separately** with its own budget. You get nudges
   when you're running high, but messaging is never blocked.

Everything else on your devices is none of this app's business.

## What's in the box

| Target | What it does |
| --- | --- |
| `NoiseGate` (iOS — iPhone **and iPad**) | Pick noise + messaging apps, exact usage with OVER banners, Focus toggle, quiet hours, budgets |
| `NoiseGateMonitor` (iOS) | Background monitor: nudges at 50/80/100% plus overtime nags at 110/125/150/200%, blocks noise at 100%, feeds the widget |
| `NoiseGateReport` (iOS) | Renders exact usage vs. budget inside the app, with a big red OVER treatment (privacy-preserving) |
| `NoiseGateShieldUI` (iOS) | Full-red block screen: **"STOP."** |
| `NoiseGateWidget` (iOS) | Home-screen + lock-screen widget; turns into a red slab when you're over budget |
| `NoiseGateMac` (macOS) | Menu-bar app: tracks flagged apps only, nags, hides noise apps, and flashes a full-screen **"NOPE."** when a blocked app surfaces; menu-bar icon flips to **OVER** |
| `NoiseGateMacWidget` (macOS) | Desktop/Notification-Center widget with the same red-slab over state |

## Features

- **Only what you flag is tracked.** Apps are chosen with Apple's
  `FamilyActivityPicker`; the selection is opaque tokens, so NoiseGate never
  even learns which apps you picked.
- **In your face, by design.** Nudges at 50/80/100% escalate to overtime nags
  at 110/125/150/200% and are delivered as *time-sensitive* notifications, so
  they punch through notification summaries and most Focus modes. Widgets and
  the app turn into red OVER slabs; the Mac flashes a full-screen "NOPE." when
  a blocked app comes forward, and keeps nagging every 5 minutes while you're
  actively over budget with blocking off.
- **Blocking, three ways**: a manual *Focus now* toggle, automatic block when
  the daily noise budget hits 100% (optional), and scheduled *quiet hours*
  (overnight windows supported).
- **Messages tracked separately** — its own budget and its own ring, never
  blocked.
- **Widgets** on iPhone/iPad (small, medium, lock-screen circular +
  rectangular) and Mac (small, medium).
- **iPhone, iPad, and Mac.** One iOS app for iPhone and iPad (all orientations
  on iPad); the Mac has its own companion since Apple offers no third-party
  Screen Time API there.

## Building

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
cd NoiseGate
xcodegen generate
open NoiseGate.xcodeproj
```

Before building:

1. **Team + identifiers.** In `project.yml`, set `DEVELOPMENT_TEAM` and replace
   the `com.example.noisegate` bundle-id prefix with your own. Update the app
   group (`group.com.example.noisegate`) in both `project.yml` and
   `Shared/AppGroup.swift` to match.
2. **Family Controls capability.** In your Apple Developer account, enable
   *Family Controls* for the iOS app, monitor, report, and shield-UI
   identifiers. It works out of the box on device for development; **App Store
   distribution requires Apple's approval** of the Family Controls & Personal
   Device Usage entitlement (apply via Apple's request form; approval is
   routinely granted for legitimate screen-time apps but takes a couple of
   weeks).
3. **Run on a real device.** Screen Time APIs are not functional in the iOS
   simulator.

First launch on iPhone: grant Screen Time access and notifications, pick your
noise apps and messaging apps in the *Blocking* tab, set budgets in *Budgets*,
add the widget. Done.

## Design notes & honest limitations

- **iOS usage numbers come from Apple's privacy wall.** Exact durations can only
  be *rendered* by the sandboxed report extension (the *Today* tab) — they
  cannot be exported to the app or the widget. The widget therefore shows a
  **floor** based on crossed budget thresholds (10% steps), marked with `≥`.
  That's the best any third-party iOS widget can legally do.
- **The iOS "Messages" tracker needs you to pick Messages once.** Apple doesn't
  let apps pre-select another app programmatically, so choose Messages (and
  WhatsApp, etc.) in the picker under *Messaging apps*.
- **macOS has no third-party Screen Time API**, so the Mac app does its own
  accounting: it samples the frontmost app every 5 seconds while you're active
  (input within the last 2 minutes) and counts only flagged bundle IDs.
  Blocking on the Mac is best-effort — a blocked app is hidden every time it
  comes to the front, which makes it effectively unusable but not launch-proof.
- **The Mac app is intentionally not sandboxed** (hiding other apps is not
  possible from the sandbox), so it's for direct distribution / personal
  builds, not the Mac App Store.
- Each device keeps its own daily tally — iPhone, iPad, and Mac are separate
  counts, not a merged total.
- Time-sensitive nudges require the user to leave "Time Sensitive
  Notifications" enabled for NoiseGate (it's on by default once notifications
  are allowed).

## Repo layout

```
NoiseGate/
├── project.yml               # XcodeGen spec (all 7 targets, entitlements, plists)
├── Shared/                   # Cross-platform: config, snapshot, day keys, gauge view
├── iOS/
│   ├── App/                  # SwiftUI app (Today / Blocking / Budgets)
│   ├── ScreenTimeShared/     # Selection store + shield controller (app + extensions)
│   ├── MonitorExtension/     # DeviceActivityMonitor: thresholds → nudges/shields
│   ├── ReportExtension/      # DeviceActivityReport: exact usage rendering
│   ├── ShieldConfigExtension/# Custom block screen
│   └── Widget/               # WidgetKit widget
└── macOS/
    ├── App/                  # Menu-bar app: tracker, nudges, enforcement
    └── Widget/               # macOS widget
```
