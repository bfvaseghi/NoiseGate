#!/usr/bin/env python3
"""Choose an installed iPhone simulator without pinning a runner's model name."""
import json
import re
import sys
import uuid


def select(devices):
    candidates = []
    for runtime, entries in devices.items():
        match = re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-(\d+)-(\d+)(?:-(\d+))?", runtime)
        if not match:
            continue
        version = tuple(int(part or 0) for part in match.groups())
        if version < (17, 4, 0):
            continue
        for device in entries:
            if not device.get("isAvailable") or not device.get("name", "").startswith("iPhone"):
                continue
            try:
                identifier = str(uuid.UUID(device["udid"]))
            except (KeyError, ValueError, TypeError, AttributeError):
                continue
            candidates.append((version, device["name"], identifier))
    if not candidates:
        raise ValueError("No available iPhone simulator with iOS 17.4 or later.")
    return max(candidates)[2]


if __name__ == "__main__":
    try:
        print(select(json.load(sys.stdin)["devices"]))
    except (ValueError, KeyError) as error:
        sys.exit(str(error))
