#!/usr/bin/env python3
"""Fast structural checks for privacy, persistence, packaging, and assets."""

from pathlib import Path
import json
import plistlib
import re
import struct
import sys


ROOT = Path(__file__).resolve().parents[1]
ERRORS = []


def require(condition, message):
    if not condition:
        ERRORS.append(message)


def text(path):
    return (ROOT / path).read_text(encoding="utf-8")


def require_absent(path, snippets, reason):
    value = text(path)
    for snippet in snippets:
        require(snippet not in value, f"{path}: {reason} ({snippet!r})")


project = text("project.yml")
require("type: extensionkit-extension" in project, "Report target must remain ExtensionKit")
require("EXAppExtensionAttributes:" in project, "Report extension attributes are missing")
require("com.apple.deviceactivityui.report-extension" in project, "Wrong report extension point")
require("com.apple.developer.family-controls: true" in project, "Family Controls entitlement missing")
require("testTargets:\n        - NoiseGateTests" in project, "iOS tests are not attached to the app scheme")
require("testTargets:\n        - NoiseGateMacTests" in project, "Mac tests are not attached to the app scheme")

target_suffixes = {
    "NoiseGate": "",
    "NoiseGateMonitor": ".monitor",
    "NoiseGateReport": ".report",
    "NoiseGateWidget": ".widget",
    "NoiseGateMac": ".mac",
    "NoiseGateMacWidget": ".mac.widget",
    "NoiseGateTests": ".tests",
    "NoiseGateMacTests": ".mac.tests",
}
target_bundle_ids = {}
current_target = None
for line in project.splitlines():
    target_match = re.fullmatch(r"  ([A-Za-z0-9]+):\s*", line)
    if target_match:
        name = target_match.group(1)
        current_target = name if name in target_suffixes else None
    bundle_match = re.match(r"\s*PRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)", line)
    if current_target and bundle_match:
        target_bundle_ids[current_target] = bundle_match.group(1)

require(set(target_bundle_ids) == set(target_suffixes),
        "Every target must have one recognized bundle identifier")
base_bundle_id = target_bundle_ids.get("NoiseGate")
if base_bundle_id:
    for target, suffix in target_suffixes.items():
        require(
            target_bundle_ids.get(target) == base_bundle_id + suffix,
            f"{target} bundle identifier must derive from {base_bundle_id!r}",
        )

project_groups = re.findall(r"^\s*-\s*(group\.[A-Za-z0-9.-]+)\s*$", project, re.MULTILINE)
require(len(project_groups) == 6, "Every production target must have one App Group")
require(len(set(project_groups)) == 1, "All production targets must share one App Group")
shared_group_match = re.search(
    r'static let id = "(group\.[A-Za-z0-9.-]+)"',
    text("Shared/AppGroup.swift"),
)
require(shared_group_match is not None, "Shared App Group constant is missing")
if project_groups and shared_group_match:
    require(project_groups[0] == shared_group_match.group(1),
            "Shared App Group constant does not match project entitlements")
    if base_bundle_id:
        require(project_groups[0] == f"group.{base_bundle_id}",
                "App Group must be group.<iOS app bundle identifier>")

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

# NOTE: a block of ~90 `require_contains` source-substring assertions used to
# live here. They pinned one implementation's exact text ("second: 59",
# "let heartbeatDue"), so any honest refactor turned CI red and trained the
# reader to ignore this file. The behaviour they stood in for is covered
# properly by Tests/iOS/SharedModelTests.swift. Keep this validator for
# cross-file invariants the compiler and the unit tests cannot see.

ios_widget = text("iOS/Widget/NoiseGateWidget.swift")
ios_family_match = re.search(r"\.supportedFamilies\(\[(.*?)\]\)", ios_widget, re.DOTALL)
require(ios_family_match is not None, "iOS widget supported families are missing")
ios_family_block = ios_family_match.group(1) if ios_family_match else ""
for family in (
    ".systemSmall",
    ".systemMedium",
    ".systemLarge",
    ".accessoryCircular",
    ".accessoryRectangular",
    ".accessoryInline",
):
    require(family in ios_family_block, f"iOS widget does not support {family}")
for layout in (
    "case .systemSmall:",
    "case .systemMedium:",
    "case .systemLarge:",
    "case .accessoryCircular:",
    "case .accessoryRectangular:",
    "case .accessoryInline:",
):
    require(layout in ios_widget, f"iOS widget has no explicit layout for {layout}")
require("AppIntentConfiguration(" in ios_widget, "iOS widget must remain configurable")
require("accuracy: .lowerBound" in ios_widget,
        "iOS widget must force lower-bound presentation")
require(".widgetURL(entry.destination.url)" in ios_widget,
        "iOS widget deep link is missing")
for forbidden in (
    "import DeviceActivity",
    "import FamilyControls",
    "import ManagedSettings",
):
    require(forbidden not in ios_widget,
            f"iOS widget crossed the Screen Time privacy wall with {forbidden!r}")

mac_widget = text("macOS/Widget/NoiseGateMacWidget.swift")
mac_family_match = re.search(r"\.supportedFamilies\(\[(.*?)\]\)", mac_widget, re.DOTALL)
require(mac_family_match is not None, "Mac widget supported families are missing")
mac_family_block = mac_family_match.group(1) if mac_family_match else ""
for family in (".systemSmall", ".systemMedium", ".systemLarge"):
    require(family in mac_family_block, f"Mac widget does not support {family}")
for layout in ("case .systemSmall:", "case .systemMedium:", "case .systemLarge:"):
    require(layout in mac_widget, f"Mac widget has no explicit layout for {layout}")
require("accuracy: .exact" in mac_widget, "Mac widget must force exact presentation")

require("CFBundleURLTypes:" in project, "iOS deep-link URL type is missing")
route_match = re.search(
    r'static let scheme = "([a-z][a-z0-9+.-]*)"',
    text("Shared/NoiseGateRoute.swift"),
)
project_scheme_match = re.search(
    r"CFBundleURLSchemes:\s*\n\s*-\s*([a-z][a-z0-9+.-]*)",
    project,
)
require(route_match is not None and project_scheme_match is not None,
        "NoiseGate URL scheme could not be parsed")
if route_match and project_scheme_match:
    require(route_match.group(1) == project_scheme_match.group(1),
            "App URL scheme does not match NoiseGateRoute")
require(".onOpenURL" in text("iOS/App/Views/ContentView.swift"),
        "iOS app does not handle widget deep links")

report = text("iOS/ReportExtension/NoiseGateReport.swift")
for forbidden in (
    "StoreKey.usageSnapshot",
    "WidgetCenter",
    "HistoryStore.record(",
    "SharedStore.shared",
    "UsageSnapshot",
    "URLSession",
):
    require(forbidden not in report,
            f"Report extension must not export exact Screen Time via {forbidden!r}")

for shared_path in (ROOT / "Shared").glob("*.swift"):
    shared_source = shared_path.read_text(encoding="utf-8")
    for forbidden in ("FamilyControls", "DeviceActivity", "ManagedSettings"):
        require(
            f"import {forbidden}" not in shared_source,
            f"{shared_path.relative_to(ROOT)} imports platform-only {forbidden}",
        )

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
