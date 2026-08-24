# AGENTS.md — working on NoiseGate

Read this before changing the project.  These rules protect the product’s
meaning, Apple’s privacy boundary, and the user’s historical data.

## Product definition

NoiseGate is a personalized screen-time tracker for iPhone, iPad, and Mac.
It has exactly two visible ledgers:

- **Distractions**: individual apps and sites the user explicitly selects.
- **Messages**: messaging apps, tracked separately.

“Noise” does **not** mean distracting apps.  Noise is the useful or neutral
activity Apple Screen Time includes but this product intentionally excludes.
Maps, reading, FaceTime, work apps, and every other unselected activity stay
invisible.

NoiseGate is observation only.  Never add shields, app hiding, termination,
enforcement, or blocking.  A separate app handles blocking.

User-facing copy is neutral and factual.  State the ledger, number, threshold,
and reset.  Do not praise, scold, joke, use exclamation points, or request
critical or time-sensitive notification priority.  Notification copy belongs
only in `Shared/NudgeText.swift`.

## Repository map

```text
project.yml                     XcodeGen source of truth for all targets
Shared/
  AppGroup.swift                App-group identifiers and stable storage keys
  SharedStore.swift             Process lock + cross-process file-lock persistence
  PrivacyInfo.xcprivacy         Required-reason declaration for UserDefaults
  BudgetConfig.swift            Budgets, notification choices, v1 migration
  UsageSnapshot.swift           Widget feed and v1 migration
  HistoryStore.swift            Rolling 30-day records and v1 migration
  NudgeText.swift               All iPhone and Mac notification copy
  WidgetPresentation.swift     Tested exact/lower-bound widget semantics
  NoiseGateRoute.swift         Stable iPhone widget deep links
  DesignSystem.swift            Adaptive visual tokens
  BudgetGauge.swift             Shared accessible ring
iOS/
  App/                          SwiftUI app: Today / Apps / Budgets
  ScreenTimeShared/             Selection safety and event-name contract
  MonitorExtension/             Threshold callbacks, floors, and nudges
  ReportExtension/              Exact private reports and charts
  Widget/                       Home Screen and Lock Screen widget
macOS/
  App/                          Menu-bar tracker and settings
  Widget/                       Mac widget
Tests/                          Migration and ledger regression tests
Scripts/validate_project.py     Cross-platform invariant audit
Design/                         Vector reference and production icon renderer
```

## Build and validate

```bash
python3 Scripts/validate_project.py
brew install xcodegen
xcodegen generate
open NoiseGate.xcodeproj
```

Build the `NoiseGate` and `NoiseGateMac` schemes.  Run `NoiseGateTests` and
`NoiseGateMacTests`.  Screen Time behavior requires a physical iPhone or iPad.

`NoiseGate.xcodeproj` is generated and gitignored.  Never hand-edit or commit
it.  Change `project.yml` instead.

Keep the placeholders synchronized until the owner replaces them:

- Team: `YOURTEAMID`
- Bundle prefix: `com.example.noisegate`
- App Group: `group.com.example.noisegate` in `project.yml` and
  `Shared/AppGroup.swift`

Use `Scripts/configure_signing.py` to replace them as one validated change.
Do not edit one identifier or App Group entry in isolation.

## Non-negotiable architecture rules

### 1. Keep shared code platform-safe

`Shared/` compiles into every target.  Foundation, SwiftUI, and Darwin are
allowed.  FamilyControls, DeviceActivity, ManagedSettings, and AppKit code must
remain in platform folders.

### 2. Respect Apple’s privacy wall

Exact iPhone usage exists only inside `NoiseGateReport`.  It cannot be written
to UserDefaults, exported to the host, sent to a server, or displayed by a
normal widget.  The iPhone widget uses the highest crossed threshold as a lower
bound and must display `≥` or “at least.”  Never present it as exact.

Device reports must stay scoped to the current device type.  Do not restore a
combined `.iPhone + .iPad` filter.

### 3. Keep selections narrow

The Family Activity pickers start with
`FamilyActivitySelection(includeEntireCategory: false)`.  Whole categories are
rejected.  A legacy selection containing a category is reset because Apple may
already have expanded it into app and domain tokens that cannot be separated
from explicit choices later.

Messages is app-only.  Its categories and domains are rejected. Effective
Distractions tokens always subtract every selected Messages token, including
paused ones. Pausing Messages makes it invisible rather than moving it into
Distractions. Never pass an
empty selection into a `DeviceActivityFilter` or empty events into monitoring
without first guarding it.  Empty can mean all activity in Apple APIs.

Paused tokens remain in the picker selection and are excluded from events and
reports.  Prune only paused tokens no longer present in the selection.  Do not
claim iOS pause is an accrual boundary.  Apple’s report applies the current
filter to the day, so resuming an app can include its earlier same-day usage.

### 4. Keep the event contract synchronized

Event names are versioned and generation-scoped, such as
`v3.g4.distractions.b45.m36.p80` and `v3.g4.msg.b60.m90.p150`. The app creates
them and the monitor accepts only the active generation. Each callback carries
its scheduled budget and exact threshold floor. This prevents a delayed event
from borrowing mutable settings or changing the new ledger.

Threshold minutes round **up**. Events use `includesPastActivity: true` so a
safe reconfiguration can rebuild today’s checkpoint floor. The iOS 17.4
deployment floor exists to keep that behavior truthful.

The daily schedule ends at `23:59:59`.  Do not reintroduce a one-minute gap.
`intervalDidStart` also fires on a mid-day restart. If the stored snapshot is
already from today, preserve its floors and nudge ledger. Only repair the
active flag if the host exited between starting monitoring and publishing it.

### 5. Reconfiguration must survive process death

Selection, pause, and budget changes persist immediately.  DeviceActivity
restarts are debounced because every restart is expensive.  The
`monitoringNeedsReconfigure` flag stays true until the replacement schedule
starts successfully.  This ensures closing the app during the debounce cannot
leave old rules active forever.

Notification preference changes persist without restarting DeviceActivity or
clearing today’s floor.

Keep report filters value-stable across SwiftUI renders. Seven-day intervals
end at the next day boundary, not `.now`, so a timer-driven view refresh does
not force the report extension to query Screen Time again.

### 6. Preserve once-per-day nudges

The `iosNudgesSent` and `macNudgesSent` ledgers deduplicate every milestone by
ledger, percent, and day. Read-modify-write through `SharedStore`. Direct
UserDefaults mutations can race across an app, extension, and widget.

For two minutes after an iOS reconfiguration, includes-past-activity callbacks
may rebuild widget floors but must not produce catch-up notifications.  This
prevents several old milestones from appearing as a burst.

The Mac sends only the highest newly crossed milestone if several become true
at once.  This prevents a notification burst after launch or a budget change.
Mirror sent Mac milestone IDs in memory so an already-fired threshold does not
lock and read the app-group store on every five-second checkpoint.

### 7. Never rewrite Mac history by reclassification

`MacLedger` has separate dictionaries for Distractions and Messages.  Time is
classified when it accrues.  Current app selections must never be used to
recompute old seconds.

The decoder migrates the v1 `seconds` dictionary once, using Messages-first
classification. Mac selections persist as one `MacSelections` value so a move
between ledgers cannot be half-written. A stale ledger is filed into history
before a new day is created, including when the app was not running at midnight.

Checkpoint on foreground-app changes.  Pause on session lock and sleep.  Cap a
single elapsed checkpoint so wake or debugger gaps cannot become tracked time.
Persist at least every 15 seconds and flush on termination.
Publish observable totals at whole-minute granularity. Keep the widget feed
alive with a lightweight 30-second heartbeat, and reload its timeline only
when visible values change or an explicit state transition requires it.

### 8. Preserve historical targets

Every `DayRecord` stores the budgets that applied to that day.  Charts compare
each historical record against its own stored target, not today’s target.
Changing today’s budget must not rewrite past records.

File the previous snapshot or ledger before resetting it.  Filter today out of
finished history before appending the live record so a day cannot be counted
twice.

### 9. Keep report contexts exact

The host and report extension string-match these four contexts:

- `Distractions`
- `Messages`
- `Distractions Week`
- `Messages Week`

The weekly report must zero-fill all seven calendar days and divide the average
by seven, not only by days that had usage.

### 10. Keep persistence atomic and migrations tolerant

Use `SharedStore` for App Group data.  Its `NSLock` protects threads and its
Darwin `lockf` lock protects processes.  Use `update` or `updateStringSet` for every
read-modify-write operation.

New Codable fields require `decodeIfPresent` defaults.  Do not remove legacy
decode keys until a deliberate migration horizon is documented.  Existing
v1 `noise*`, selection, pause, snapshot, history, and Mac ledger values must
continue to load.

## Design rules

- Use `NG.*` colors and `Font.ng*` typography.  Do not add raw view colors.
- Orange (`NG.distraction`) means Distractions.  Teal means Messages.  Red is
  reserved for the brand and reached-budget state.
- iPhone widget values always force lower-bound wording at the presentation
  boundary, even if a legacy snapshot omitted its `isFloor` marker.
- iPhone weekly widgets report only confirmed budget crossings. Never label a
  checkpoint-only or missing day as under budget.
- Respect Reduce Motion.  Every visual gauge needs a combined accessibility
  label and value.
- `Design/NoiseGateIcon.svg` is the editable vector reference, and
  `Design/render_icon.py` is the deterministic production renderer. Keep their
  geometry and colors synchronized. Committed PNGs must remain opaque RGB and
  match their asset-catalog dimensions.
- Keep the interface calm, legible, and specific.  “Everything else is
  excluded as noise” is the core promise.

## Conventions

- Swift 5 language mode, SwiftUI, iOS 17.4+, macOS 14+, and no runtime dependencies.
- Four-space indentation and `// MARK:` sections.
- Comments explain privacy, migration, or platform constraints.
- Commit messages use an imperative subject and a body that explains behavior.
- Do not commit `.DS_Store`, DerivedData, or `NoiseGate.xcodeproj`.
