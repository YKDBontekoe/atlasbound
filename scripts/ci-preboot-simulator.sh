#!/usr/bin/env bash
# Resolve a preferred iPhone simulator and start booting it.
# Used by CI to overlap cold boot with artifact download.
set -euo pipefail

SIMULATOR_NAME="${SIMULATOR_NAME:-}"

resolve_simulator() {
  if [[ -n "$SIMULATOR_NAME" ]]; then
    echo "$SIMULATOR_NAME"
    return
  fi

  xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)
devices = []
for runtime, items in data.get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    for device in items:
        if device.get("isAvailable") and str(device.get("name", "")).startswith("iPhone"):
            devices.append(device["name"])
preferred = ["iPhone 16", "iPhone 16 Pro", "iPhone 15", "iPhone 15 Pro"]
for name in preferred:
    if name in devices:
        print(name)
        raise SystemExit(0)
if not devices:
    raise SystemExit("No available iPhone simulators")
print(devices[0])
'
}

SIMULATOR_NAME="$(resolve_simulator)"
echo "Pre-booting simulator: ${SIMULATOR_NAME}"
xcrun simctl boot "$SIMULATOR_NAME" 2>/dev/null || true

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "SIMULATOR_NAME=${SIMULATOR_NAME}" >> "$GITHUB_ENV"
fi
