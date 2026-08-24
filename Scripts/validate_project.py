#!/usr/bin/env python3
"""Fast structural checks for privacy, persistence, packaging, and assets."""

from pathlib import Path
import json
import plistlib
import struct
import sys


ROOT = Path(__file__).resolve().parents[1]
ERRORS = []


def require(condition, message):
    if not condition:
        ERRORS.append(message)


def text(path):
    return (ROOT / path).read_text(encoding="utf-8")


def require_contains(path, snippets):
    value = text(path)
    for snippet in snippets:
        require(snippet in value, f"{path}: missing {snippet!r}")


project = text("project.yml")
require("type: extensionkit-extension" in project, "Report target must remain ExtensionKit")
require("EXAppExtensionAttributes:" in project, "Report extension attributes are missing")
require("com.apple.deviceactivityui.report-extension" in project, "Wrong report extension point")
require("com.apple.developer.family-controls: true" in project, "Family Controls entitlement missing")
require("testTargets:\n        - NoiseGateTests" in project, "iOS tests are not attached to the app scheme")
require("testTargets:\n        - NoiseGateMacTests" in project, "Mac tests are not attached to the app scheme")

privacy_path = ROOT / "Shared/PrivacyInfo.xcprivacy"
require(privacy_path.exists(), "Shared privacy manifest is missing")
if privacy_path.exists():
    with privacy_path.open("rb") as file:
        privacy = plistlib.load(file)
    accessed = {
        item.get("NSPrivacyAccessedAPIType"): set(
            item.get("NSPrivacyAccessedAPITypeReasons", [])
        )
        for item in privacy.get("NSPrivacyAccessedAPITypes", [])
    }
    user_defaults_reasons = accessed.get(
        "NSPrivacyAccessedAPICategoryUserDefaults",
        set(),
    )
    require("1C8F.1" in user_defaults_reasons, "App Group UserDefaults reason is missing")
    require("CA92.1" in user_defaults_reasons, "Standard UserDefaults fallback reason is missing")

require_contains("iOS/ScreenTimeShared/SelectionStore.swift", [
    "FamilyActivitySelection(includeEntireCategory: false)",
    "guard selection.categoryTokens.isEmpty",
    "guard selection.categoryTokens.isEmpty,",
])
require_contains("iOS/App/Model/ScreenTimeModel.swift", [
    ".subtracting(messagesSelection.applicationTokens)",
    "guard !events.isEmpty else",
    "second: 59",
    "includesPastActivity: true",
    "monitoringNeedsReconfigure",
    "monitoringAcceptsCallbacks",
    "monitoringGeneration",
    "monitoringSchemaVersion",
    "monitoringConfiguredAt",
])
require_contains("iOS/ScreenTimeShared/ThresholdEvent.swift", [
    "static let schemaVersion = 3",
    "budgetMinutes: Int",
    "thresholdMinutes: Int",
    "exactThreshold == thresholdMinutes",
])
require_contains("iOS/MonitorExtension/NoiseGateMonitor.swift", [
    "parsed.generation",
    "parsed.budgetMinutes",
    "parsed.thresholdMinutes",
])
require_contains("Shared/UsageSnapshot.swift", [
    "distractionsConfigured",
    "messagesConfigured",
    "monitoringIsActive: snap.monitoringIsActive",
    "updatedAt: snap.updatedAt",
])
require_contains("Shared/HistoryStore.swift", [
    "static func canonicalized",
    "canonicalized(records).suffix(maxDays)",
])
require_contains("iOS/App/Views/TodayView.swift", [
    ".init([.iPhone])",
    "categories: []",
    "activeDistractionApps",
    "end: todayInterval.end",
])
require_contains("Shared/SharedStore.swift", [
    "NSLock()",
    "Darwin.lockf(descriptor, F_LOCK, 0)",
    "Darwin.lockf(descriptor, F_ULOCK, 0)",
    "func update<T: Codable>",
])
require_contains("macOS/App/MacModel.swift", [
    "distractionSecondsByBundleID",
    "messagesSecondsByBundleID",
    "legacyUnclassifiedSeconds",
    "NSWorkspace.willSleepNotification",
    "SMAppService.mainApp.register()",
    "@Published private(set) var distractionMinutesToday",
    "private var nudgesSentToday",
    "let heartbeatDue",
])

swift = "\n".join(path.read_text(encoding="utf-8") for path in ROOT.rglob("*.swift"))
for forbidden in ("ManagedSettingsStore(", ".shield.applications", "forceTerminate()"):
    require(forbidden not in swift, f"Observation-only invariant violated by {forbidden!r}")

contexts = {
    'Self("Distractions")',
    'Self("Messages")',
    'Self("Distractions Week")',
    'Self("Messages Week")',
}
for path in ("iOS/App/Views/TodayView.swift", "iOS/ReportExtension/NoiseGateReport.swift"):
    value = text(path)
    for context in contexts:
        require(context in value, f"{path}: report context drift for {context}")

for contents in ROOT.rglob("*.xcassets/**/Contents.json"):
    try:
        json.loads(contents.read_text(encoding="utf-8"))
    except Exception as error:
        ERRORS.append(f"{contents.relative_to(ROOT)}: invalid JSON: {error}")


def png_info(path):
    data = path.read_bytes()[:26]
    require(data[:8] == b"\x89PNG\r\n\x1a\n", f"{path.relative_to(ROOT)} is not PNG")
    if len(data) < 26:
        return None
    width, height = struct.unpack(">II", data[16:24])
    color_type = data[25]
    return width, height, color_type


for platform in ("iOS/App", "macOS/App"):
    icon_dir = ROOT / platform / "Assets.xcassets/AppIcon.appiconset"
    manifest = json.loads((icon_dir / "Contents.json").read_text(encoding="utf-8"))
    filenames = [image["filename"] for image in manifest["images"]]
    require(
        len(filenames) == len(set(filenames)),
        f"{icon_dir.relative_to(ROOT)} references one render from multiple slots",
    )
    for image in manifest["images"]:
        path = icon_dir / image["filename"]
        require(path.exists(), f"Missing app icon {path.relative_to(ROOT)}")
        if path.exists():
            info = png_info(path)
            if info:
                width, height, color_type = info
                expected = round(float(image["size"].split("x")[0]) * int(image["scale"][0]))
                require((width, height) == (expected, expected),
                        f"{path.relative_to(ROOT)} is {width}x{height}, expected {expected}")
                require(color_type == 2, f"{path.relative_to(ROOT)} must be opaque RGB")
    assigned = set(filenames)
    extras = {path.name for path in icon_dir.glob("*.png")} - assigned
    require(
        not extras,
        f"{icon_dir.relative_to(ROOT)} has unassigned PNGs: {sorted(extras)}",
    )

if ERRORS:
    print("NoiseGate validation failed:")
    for error in ERRORS:
        print(f"- {error}")
    sys.exit(1)

print(f"NoiseGate structural validation passed ({len(list(ROOT.rglob('*.swift')))} Swift files).")
