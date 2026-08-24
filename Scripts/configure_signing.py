#!/usr/bin/env python3
"""Configure NoiseGate's Apple Team, bundle IDs, and App Group together."""

from argparse import ArgumentParser, ArgumentTypeError
from difflib import unified_diff
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
PROJECT_PATH = ROOT / "project.yml"
APP_GROUP_PATH = ROOT / "Shared/AppGroup.swift"

TARGET_SUFFIXES = {
    "NoiseGate": "",
    "NoiseGateMonitor": ".monitor",
    "NoiseGateReport": ".report",
    "NoiseGateWidget": ".widget",
    "NoiseGateMac": ".mac",
    "NoiseGateMacWidget": ".mac.widget",
    "NoiseGateTests": ".tests",
    "NoiseGateMacTests": ".mac.tests",
}


PLACEHOLDER_TEAM_IDS = {"YOURTEAMID", "ABCDE12345"}
PLACEHOLDER_APP_BUNDLE_IDS = {
    "com.example.noisegate",
    "com.yourname.noisegate",
}


def validate_team_id(value):
    if not re.fullmatch(r"[A-Z0-9]{10}", value):
        raise ArgumentTypeError("Team ID must be exactly 10 uppercase letters or digits")
    if value in PLACEHOLDER_TEAM_IDS:
        raise ArgumentTypeError("Replace the example with your real Apple Team ID")
    return value


def validate_app_bundle_id(value):
    component = r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?"
    if not re.fullmatch(rf"{component}(?:\.{component})+", value):
        raise ArgumentTypeError(
            "App Bundle ID must be lowercase reverse-DNS text, such as "
            "com.bfvaseghi.noisegate"
        )
    if value.startswith("group."):
        raise ArgumentTypeError("Pass the app Bundle ID without the group. prefix")
    if value in PLACEHOLDER_APP_BUNDLE_IDS:
        raise ArgumentTypeError("Replace the example with your permanent app Bundle ID")
    return value


def configured_project(source, team_id, app_bundle_id):
    lines = source.splitlines(keepends=True)
    current_target = None
    replaced_targets = set()
    team_replacements = 0
    group_replacements = 0
    result = []

    for line in lines:
        target_match = re.fullmatch(r"  ([A-Za-z0-9]+):\s*\n?", line)
        if target_match:
            name = target_match.group(1)
            current_target = name if name in TARGET_SUFFIXES else None

        if re.match(r"\s*DEVELOPMENT_TEAM:", line):
            indent = line[:len(line) - len(line.lstrip())]
            line = f'{indent}DEVELOPMENT_TEAM: "{team_id}"\n'
            team_replacements += 1
        elif current_target and re.match(r"\s*PRODUCT_BUNDLE_IDENTIFIER:", line):
            indent = line[:len(line) - len(line.lstrip())]
            identifier = app_bundle_id + TARGET_SUFFIXES[current_target]
            line = f"{indent}PRODUCT_BUNDLE_IDENTIFIER: {identifier}\n"
            replaced_targets.add(current_target)
        elif re.match(r"\s*- group\.[A-Za-z0-9.-]+\s*$", line):
            indent = line[:len(line) - len(line.lstrip())]
            line = f"{indent}- group.{app_bundle_id}\n"
            group_replacements += 1
        result.append(line)

    missing = set(TARGET_SUFFIXES) - replaced_targets
    if missing:
        raise ValueError(f"Could not find bundle IDs for: {', '.join(sorted(missing))}")
    if team_replacements != 1:
        raise ValueError(f"Expected one DEVELOPMENT_TEAM setting, found {team_replacements}")
    if group_replacements != 6:
        raise ValueError(f"Expected six App Group entries, found {group_replacements}")
    return "".join(result)


def configured_app_group(source, app_bundle_id):
    result, count = re.subn(
        r'static let id = "group\.[A-Za-z0-9.-]+"',
        f'static let id = "group.{app_bundle_id}"',
        source,
    )
    if count != 1:
        raise ValueError(f"Expected one Shared App Group constant, found {count}")
    return result


def show_diff(path, before, after):
    relative = path.relative_to(ROOT)
    sys.stdout.writelines(unified_diff(
        before.splitlines(keepends=True),
        after.splitlines(keepends=True),
        fromfile=f"current/{relative}",
        tofile=f"proposed/{relative}",
    ))


def replace_text_atomically(path, content):
    descriptor, temporary_name = tempfile.mkstemp(
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
        text=True,
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as temporary:
            temporary.write(content)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_path, path)
    finally:
        if temporary_path.exists():
            temporary_path.unlink()


def apply_and_validate(changes):
    originals = {path: before for path, before, _ in changes}
    try:
        for path, _, after in changes:
            replace_text_atomically(path, after)
        validation = subprocess.run(
            [sys.executable, str(ROOT / "Scripts/validate_project.py")],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        if validation.returncode != 0:
            detail = validation.stdout.strip() or validation.stderr.strip()
            raise ValueError(f"Project validation failed after configuration:\n{detail}")
    except Exception:
        for path, before in originals.items():
            replace_text_atomically(path, before)
        raise


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--team-id", required=True, type=validate_team_id)
    parser.add_argument(
        "--app-bundle-id",
        required=True,
        type=validate_app_bundle_id,
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="write the reviewed values instead of showing a preview",
    )
    args = parser.parse_args()

    project_before = PROJECT_PATH.read_text(encoding="utf-8")
    group_before = APP_GROUP_PATH.read_text(encoding="utf-8")
    project_after = configured_project(
        project_before,
        args.team_id,
        args.app_bundle_id,
    )
    group_after = configured_app_group(group_before, args.app_bundle_id)

    if not args.apply:
        show_diff(PROJECT_PATH, project_before, project_after)
        show_diff(APP_GROUP_PATH, group_before, group_after)
        print("Preview only. Run again with --apply after checking these values.")
        return

    apply_and_validate([
        (PROJECT_PATH, project_before, project_after),
        (APP_GROUP_PATH, group_before, group_after),
    ])
    print(f"Configured Team {args.team_id}")
    print(f"App Bundle ID: {args.app_bundle_id}")
    print(f"App Group: group.{args.app_bundle_id}")
    print("Next: register the identifiers in Apple Developer, then run xcodegen generate.")


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        raise SystemExit(f"Configuration error: {error}") from error
