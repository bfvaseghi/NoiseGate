#!/usr/bin/env python3
"""Choose an installed iPhone simulator without pinning a runner's model name."""
import argparse
import json
import re
import sys
import uuid


def select(devices, sdk_version=None):
    maximum = None
    if sdk_version is not None:
        if not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", sdk_version):
            raise ValueError("Invalid iPhone simulator SDK version.")
        maximum = tuple(int(part) for part in sdk_version.split("."))
        maximum += (0,) * (3 - len(maximum))
    candidates = []
    for runtime, entries in devices.items():
        match = re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-(\d+)-(\d+)(?:-(\d+))?", runtime)
        if not match:
            continue
        version = tuple(int(part or 0) for part in match.groups())
        if version < (17, 4, 0) or (maximum is not None and version > maximum):
            continue
        for device in entries:
            if not device.get("isAvailable") or not device.get("name", "").startswith("iPhone"):
                continue
            try:
                identifier = device["udid"]
                # Validate without changing the spelling returned by simctl.
                # xcodebuild matches the destination identifier literally.
                uuid.UUID(identifier)
            except (KeyError, ValueError, TypeError, AttributeError):
                continue
            name = device["name"]
            # Prefer a plain Pro model (the sizes the previews are laid out
            # for) over the SE or a Max when several share the runtime.
            pro = 1 if re.fullmatch(r"iPhone \d+ Pro", name) else 0
            candidates.append((version, pro, name, identifier))
    if not candidates:
        raise ValueError("No available iPhone simulator with iOS 17.4 or later compatible with the selected SDK.")
    return max(candidates)[3]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk-version", required=True,
                        help="Version from xcrun --sdk iphonesimulator --show-sdk-version")
    args = parser.parse_args()
    try:
        print(select(json.load(sys.stdin)["devices"], args.sdk_version))
    except (ValueError, KeyError) as error:
        sys.exit(str(error))
