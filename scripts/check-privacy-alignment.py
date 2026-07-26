#!/usr/bin/env python3
"""Fail if Info.plist location privacy strings drift from AltStore apps.json."""

from __future__ import annotations

import argparse
import json
import plistlib
import sys
from pathlib import Path


REQUIRED_KEYS = (
    "NSLocationWhenInUseUsageDescription",
    "NSLocationAlwaysAndWhenInUseUsageDescription",
)


def load_plist_privacy(path: Path) -> dict[str, str]:
    with path.open("rb") as fh:
        plist = plistlib.load(fh)
    values: dict[str, str] = {}
    for key in REQUIRED_KEYS:
        value = plist.get(key)
        if not isinstance(value, str) or not value.strip():
            raise SystemExit(f"error: {path} missing non-empty string for {key}")
        values[key] = value.strip()
    return values


def load_altstore_privacy(path: Path) -> dict[str, str]:
    with path.open(encoding="utf-8") as fh:
        source = json.load(fh)
    try:
        privacy = source["apps"][0]["appPermissions"]["privacy"]
    except (KeyError, IndexError, TypeError) as exc:
        raise SystemExit(f"error: {path} missing apps[0].appPermissions.privacy") from exc

    values: dict[str, str] = {}
    for entry in privacy:
        name = entry.get("name")
        usage = entry.get("usageDescription")
        if name in REQUIRED_KEYS:
            if not isinstance(usage, str) or not usage.strip():
                raise SystemExit(f"error: {path} missing usageDescription for {name}")
            values[name] = usage.strip()

    missing = [key for key in REQUIRED_KEYS if key not in values]
    if missing:
        raise SystemExit(f"error: {path} missing privacy entries: {', '.join(missing)}")
    return values


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--plist",
        type=Path,
        default=Path("Atlasbound/Info.plist"),
        help="Path to Info.plist",
    )
    parser.add_argument(
        "--apps-json",
        type=Path,
        default=Path("altstore/apps.json"),
        help="Path to AltStore apps.json",
    )
    args = parser.parse_args()

    if not args.plist.is_file():
        print(f"error: plist not found: {args.plist}", file=sys.stderr)
        return 1
    if not args.apps_json.is_file():
        print(f"error: apps.json not found: {args.apps_json}", file=sys.stderr)
        return 1

    plist_values = load_plist_privacy(args.plist)
    altstore_values = load_altstore_privacy(args.apps_json)

    mismatches: list[str] = []
    for key in REQUIRED_KEYS:
        left = plist_values[key]
        right = altstore_values[key]
        if left != right:
            mismatches.append(
                f"{key}:\n  Info.plist: {left!r}\n  apps.json:  {right!r}"
            )

    if mismatches:
        print("Privacy string mismatch between Info.plist and altstore/apps.json:", file=sys.stderr)
        for item in mismatches:
            print(item, file=sys.stderr)
        return 1

    print("Privacy strings aligned for:")
    for key in REQUIRED_KEYS:
        print(f"  - {key}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
