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
removes.

**NoiseGate never blocks, hides, or closes an app — by design, not by
omission.**  It exists to measure the time you give to apps you have decided
are distracting, so you can see the number and judge it yourself.  Blocking
is a different job for a different app.  The build fails if restriction APIs
are ever added.

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

The widgets use a signal-first hierarchy: Distractions is primary, Messages is
secondary, and no all-screen total appears. Long-press a widget and choose
**Edit Widget** to emphasize Distractions or Messages. Automatic mode prefers
Distractions and falls back to Messages when that is the only configured
ledger. iPhone includes small, medium, large, circular, rectangular, and inline
Lock Screen layouts. Mac includes small, medium, and large layouts.

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
total. The large widget describes days at or beyond the budget as confirmed
crossings. It does not describe other days as under budget because callbacks
can lag and the widget cannot read exact Screen Time. The report is scoped to
the current device type, so an iPad does not silently inflate an iPhone report.

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
```

The bundle identifiers are set: `com.bardia.noisegate` for the iPhone app,
`com.bardia.noisegate.mac` for the Mac app, derived identifiers for the
extensions, and the App Group `group.com.bardia.noisegate` on all six
production targets. Only the Team ID is still a placeholder. Configure it as
one synchronized change; the command first shows a diff:

```bash
python3 Scripts/configure_signing.py \
  --team-id YOUR_REAL_TEAM_ID \
  --app-bundle-id com.bardia.noisegate
```

Check the preview, then add `--apply`. The Team ID is the 10-character value in
Apple Developer **Membership details**. The script derives every extension
identifier and the App Group from the app Bundle ID so one target cannot
accidentally use a different value; pass a different `--app-bundle-id` only to
move the whole app to another prefix. The TestFlight workflow below passes the
team on the command line, so a cloud build never needs this step.

Before building on a physical device:

1. Register the script's App Group in **Certificates, Identifiers & Profiles**.
2. Register explicit App IDs for the iOS app, monitor, report, iOS widget, Mac
   app, and Mac widget.
3. Attach the App Group to all six production identifiers.
4. Enable Family Controls (Development) for the iOS app, monitor, and report
   identifiers.
5. Sign in under Xcode **Settings → Accounts**.
6. Connect the iPhone or iPad, trust the Mac, and enable Developer Mode on the
   device.
7. Run `xcodegen generate`, open `NoiseGate.xcodeproj`, choose the `NoiseGate`
   scheme and the connected device, then click Run. Screen Time data does not
   work in the simulator.

NoiseGate targets iOS 17.4 or later so a rule change can rebuild today's
checkpoint lower bound from past activity instead of presenting a false zero.

Development builds work with the Family Controls capability.  App Store
and TestFlight distribution require Apple’s approval for the Family Controls
(Distribution) managed capability on the iOS app, monitor extension, and report
extension separately; the next section says how. Public distribution also
needs a privacy-policy URL in App Store Connect and an accessible
privacy-policy link inside the app. That link is not yet included in
NoiseGate.

## Install on your iPhone and Mac

With a paid Apple Developer account, **Actions → TestFlight → Run workflow**
signs both apps in the cloud and uploads them to TestFlight, so each installs
from the TestFlight app with no cable and no Xcode, and every later run
arrives as an update. Nothing goes to the App Store. The one-time setup:

1. Add four repository secrets (Settings → Secrets and variables → Actions):
   `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_P8` (the full
   text of the API key's `.p8` file). The key comes from App Store Connect →
   Users and Access → Integrations → App Store Connect API, role App Manager.
2. Create two app records in App Store Connect (My Apps → + → New App): an
   iOS app with bundle ID `com.bardia.noisegate` and a macOS app with
   `com.bardia.noisegate.mac`. The Mac app is a native macOS app with an
   identifier of its own, so it has a record of its own.
3. For the iPhone app, request the Family Controls (Distribution) capability
   from Apple for the app, monitor, and report identifiers at
   <https://developer.apple.com/contact/request/family-controls-distribution>.
   A development build does not need it. A TestFlight build cannot be signed
   without it, and the workflow says so when that is what stopped it.
   Approval usually takes days.
4. Run the workflow. Its **platform** input chooses `both`, `iphone`, or
   `mac`. The Mac app needs no approval, so `mac` ships now.
5. In App Store Connect → TestFlight, add yourself as an internal tester.
   Install the TestFlight app on the iPhone and on the Mac, accept the
   invitation, and install NoiseGate from it. The Mac app lives in the menu
   bar: open it once from Applications and it stays there with no Dock icon.
   Its widget is in Notification Center and on the desktop.

TestFlight builds expire after ninety days; re-running the workflow renews
them. Each run uploads a new build number, and every bundle in an archive
carries the same one, because the Info.plists refer to the build setting
rather than spelling a number.

## Validate

Run the fast structural audit anywhere Python 3 is available:

```bash
python3 Scripts/validate_project.py
python3 -m unittest discover -s Tests/python
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
tests on every pull request, and on demand signs and uploads both apps to
TestFlight (`.github/workflows/testflight.yml`).

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
