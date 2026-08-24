# NoiseGate

**Screen time without the noise.**

Apple Screen Time combines distracting feeds with maps, reading, work, calls,
and everything else the screen happens to display.  That total is noisy.  It
does not answer the useful question: *how much time did I give to apps that I
personally consider distracting?*

NoiseGate keeps only two explicit ledgers:

1. **Distractions** for the apps and sites the user deliberately chooses.
2. **Messages** for conversation time, kept separate.

Everything else is excluded.  That excluded activity is the noise NoiseGate
removes.  NoiseGate never blocks, hides, or closes an app.

## Product principles

- **Only explicit choices count.** The user selects individual apps. The Mac
  starts with Apple Messages selected, and every other app starts invisible.
  Whole categories are rejected because they can silently pull useful activity
  back into the total.
- **Messages cannot inflate Distractions.**  If the same opaque app token
  appears in both lists, Messages wins and the Distractions report subtracts
  it.
- **Paused is not deleted.**  A selected app or site can be paused without
  losing the picker selection.  On iOS, Apple applies the current list to the
  day’s report.  Turning an app back on can therefore include its earlier
  activity from the same day.  The interface does not pretend otherwise.
- **Nudges are optional and factual.**  The user can enable 50%, 80%, 100%,
  150%, and 200% checkpoints.  Each fires at most once per day and never uses
  critical or time-sensitive priority.
- **Existing data survives upgrades.**  The v1 `noise*` fields and Mac ledger
  decode into the corrected Distractions model. Budgets, narrow selections,
  today’s tally, and history remain intact. A broad legacy category is removed
  with a one-time notice because keeping it would restore the noise.

## What ships

| Target | Purpose |
| --- | --- |
| `NoiseGate` | iPhone and iPad app for Today, Apps, and Budgets |
| `NoiseGateMonitor` | Screen Time thresholds, widget checkpoints, and nudges |
| `NoiseGateReport` | Exact private usage reports and seven-day charts |
| `NoiseGateWidget` | Home Screen and Lock Screen widgets |
| `NoiseGateMac` | Idle-aware native menu-bar tracker |
| `NoiseGateMacWidget` | Desktop and Notification Center widget |

Every production bundle also embeds `Shared/PrivacyInfo.xcprivacy`, which
declares the App Group and app-local UserDefaults access NoiseGate uses for its
on-device settings and ledgers. NoiseGate declares no tracking or collected
data in that manifest.

The Mac app can launch at login.  It checkpoints foreground changes, pauses
immediately when the session locks or sleeps, and persists every 15 seconds.
Time is classified when it accrues, so removing or reclassifying an app later
cannot rewrite today’s earlier totals.

## iPhone privacy and widget accuracy

Apple keeps exact Screen Time durations inside the
`DeviceActivityReportExtension` privacy sandbox.  The Today and 7 Days views
can render exact values there, but the host app and a normal widget cannot read
them.

The iPhone widget therefore shows a truthful lower bound based on crossed
thresholds.  A value such as `≥ 20m` means “at least 20 minutes,” not an exact
total.  The report is scoped to the current device type, so an iPad does not
silently inflate an iPhone report.

The exact seven-day report answers “how much time did the apps selected now
receive on each of the last seven days?”  Apple does not expose a historical
selection ledger, so NoiseGate does not claim it can reconstruct which apps
were selected on a past date.

## Mac accounting

macOS offers no third-party Screen Time API.  NoiseGate records the frontmost
app while the Mac is active and input is recent.  It pauses after two minutes
without input and while the Mac is locked or asleep.  Only selected bundle
identifiers enter either ledger.

Mac totals are exact for the tracker’s own observations.  Browser domains are
not inspected.  Selecting a browser would count the browser as an app, so the
recommended setup is to select only native distracting apps.

## Build

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
xcodegen generate
open NoiseGate.xcodeproj
```

Before building:

1. Replace `YOURTEAMID` in `project.yml` with the Apple development team.
2. Replace every `com.example.noisegate` bundle identifier.
3. Change `group.com.example.noisegate` in both `project.yml` and
   `Shared/AppGroup.swift` to the matching App Group.
4. Create that App Group in the Apple Developer portal and attach it to every
   app and extension identifier that uses it.
5. Enable Family Controls for the iOS app, monitor, and report identifiers.
6. Run the iOS app on a physical device.  Screen Time data does not work in the
   simulator.

NoiseGate targets iOS 17.4 or later so a rule change can rebuild today's
checkpoint lower bound from past activity instead of presenting a false zero.

Development builds work with the Family Controls capability.  App Store
distribution requires Apple’s approval for the Family Controls Personal Device
Usage entitlement.

## Validate

Run the fast structural audit anywhere Python 3 is available:

```bash
python3 Scripts/validate_project.py
```

On a Mac with Xcode:

```bash
xcodegen generate
xcodebuild -project NoiseGate.xcodeproj -scheme NoiseGate \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project NoiseGate.xcodeproj -scheme NoiseGate \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO test
xcodebuild -project NoiseGate.xcodeproj -scheme NoiseGateMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project NoiseGate.xcodeproj -scheme NoiseGateMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

GitHub Actions runs the structural audit, both builds, and the model migration
tests on every pull request.

## Repository map

```text
Shared/                     Models, migration, locked app-group store, design
iOS/App/                    SwiftUI host app
iOS/ScreenTimeShared/       Opaque selections and event contract
iOS/MonitorExtension/       Threshold handling and widget checkpoint feed
iOS/ReportExtension/        Exact private Today and 7 Days reports
iOS/Widget/                 iPhone and iPad widgets
macOS/App/                  Menu-bar tracker and settings
macOS/Widget/               Mac widget
Tests/                      Migration and ledger regression tests
Scripts/validate_project.py Cross-platform structural audit
Design/                     Vector reference and deterministic production renderer
project.yml                 XcodeGen source of truth
```

Read [AGENTS.md](AGENTS.md) before changing the architecture.  It records the
privacy boundaries, migration rules, and historical-data invariants that are
easy to break even when a change appears harmless.
