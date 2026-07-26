#!/usr/bin/env python3
"""Generate or update an AltStore / SideStore compatible source JSON."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_SOURCE: dict[str, Any] = {
    "name": "Atlasbound",
    "subtitle": "Location-based exploration RPG",
    "description": (
        "Walk, run, cycle, or drive to discover hexagonal map tiles. "
        "Revisiting awards familiarity XP. Sideload via AltStore or SideStore."
    ),
    "tintColor": "#2E8F6B",
    "website": "",
    "featuredApps": ["com.atlasbound.app"],
    "apps": [
        {
            "name": "Atlasbound",
            "bundleIdentifier": "com.atlasbound.app",
            "developerName": "Youri Bontekoe",
            "subtitle": "Discover the world, one hex at a time",
            "localizedDescription": (
                "Atlasbound is a location-based exploration RPG for iPhone.\n\n"
                "• Discover hexagonal tiles as you walk, run, cycle, or drive\n"
                "• Earn familiarity XP when revisiting tiles\n"
                "• Adjustable hex size (60 / 80 / 100 m)\n"
                "• All progress stored on-device"
            ),
            "iconURL": "",
            "tintColor": "#2E8F6B",
            "category": "games",
            "versions": [],
            "appPermissions": {
                "entitlements": [],
                "privacy": [
                    {
                        "name": "NSLocationWhenInUseUsageDescription",
                        "usageDescription": (
                            "Atlasbound uses your location while recording an activity "
                            "to discover map tiles along your route."
                        ),
                    },
                    {
                        "name": "NSLocationAlwaysAndWhenInUseUsageDescription",
                        "usageDescription": (
                            "Atlasbound can continue recording your route in the background "
                            "so driving and walking stay passive."
                        ),
                    },
                ],
            },
        }
    ],
    "news": [],
}


def load_source(path: Path | None) -> dict[str, Any]:
    if path and path.is_file():
        with path.open(encoding="utf-8") as fh:
            return json.load(fh)
    return json.loads(json.dumps(DEFAULT_SOURCE))


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def upsert_version(source: dict[str, Any], version_entry: dict[str, Any]) -> None:
    apps = source.setdefault("apps", [])
    if not apps:
        raise SystemExit("source has no apps entry")

    app = apps[0]
    versions: list[dict[str, Any]] = app.setdefault("versions", [])

    # Newest first — AltStore compares index 0 for updates.
    versions = [
        v
        for v in versions
        if not (
            v.get("version") == version_entry["version"]
            and str(v.get("buildVersion", "")) == str(version_entry["buildVersion"])
        )
    ]
    versions.insert(0, version_entry)
    app["versions"] = versions


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", type=Path, required=True, help="Path to the built .ipa")
    parser.add_argument("--download-url", required=True, help="Public URL of the .ipa")
    parser.add_argument("--version", required=True, help="CFBundleShortVersionString")
    parser.add_argument("--build", required=True, help="CFBundleVersion / buildVersion")
    parser.add_argument("--date", default="", help="ISO-8601 release date (UTC default: now)")
    parser.add_argument("--notes", default="", help="What's new for this version")
    parser.add_argument("--icon-url", default="", help="Public URL for the app icon")
    parser.add_argument("--website", default="", help="Source / project website URL")
    parser.add_argument("--min-os", default="17.0", help="Minimum iOS version")
    parser.add_argument(
        "--input",
        type=Path,
        default=None,
        help="Existing apps.json to merge into (keeps version history)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="Where to write the updated AltStore source JSON",
    )
    args = parser.parse_args()

    if not args.ipa.is_file():
        print(f"error: IPA not found: {args.ipa}", file=sys.stderr)
        return 1

    source = load_source(args.input)
    size = args.ipa.stat().st_size
    sha256 = file_sha256(args.ipa)
    date = args.date or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    notes = args.notes or f"Atlasbound {args.version} (build {args.build})"

    if args.website:
        source["website"] = args.website
    if args.icon_url and source.get("apps"):
        source["apps"][0]["iconURL"] = args.icon_url
        source.setdefault("iconURL", args.icon_url)

    version_entry = {
        "version": args.version,
        "buildVersion": str(args.build),
        "date": date,
        "localizedDescription": notes,
        "downloadURL": args.download_url,
        "size": size,
        "sha256": sha256,
        "minOSVersion": args.min_os,
    }
    upsert_version(source, version_entry)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as fh:
        json.dump(source, fh, indent=2, ensure_ascii=False)
        fh.write("\n")

    print(f"Wrote {args.output} ({len(source['apps'][0]['versions'])} version(s))")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
