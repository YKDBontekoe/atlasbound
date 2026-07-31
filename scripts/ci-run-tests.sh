#!/usr/bin/env bash
# Start an iOS Simulator, compile while it boots, then run the selected tests.
# Used by GitHub Actions and local CI parity runs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="${SCHEME:-Atlasbound}"
PROJECT="${PROJECT:-Atlasbound.xcodeproj}"
RESULT_BUNDLE="${RESULT_BUNDLE:-TestResults.xcresult}"
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

bootstrap_snapshots_if_needed() {
  local count
  count="$(find AtlasboundTests/Visual/__Snapshots__ -name '*.png' 2>/dev/null | wc -l | tr -d ' ')"
  # Forward CI into the simulator test host (plain CI= is not inherited by XCTest).
  export TEST_RUNNER_CI=true
  if [[ "$count" -eq 0 ]]; then
    echo "No reference PNGs — recording snapshots this run"
    export BOOTSTRAP_SNAPSHOTS=1
    export RECORD_SNAPSHOTS=1
    export TEST_RUNNER_BOOTSTRAP_SNAPSHOTS=1
    export TEST_RUNNER_RECORD_SNAPSHOTS=1
  else
    echo "Found ${count} reference PNG(s)"
  fi
}

start_simulator() {
  local name="$1"
  xcrun simctl boot "$name" 2>/dev/null || true
}

prepare_simulator() {
  local name="$1"
  xcrun simctl bootstatus "$name" -b
  xcrun simctl privacy "$name" grant location-always com.atlasbound.app || true
  xcrun simctl privacy "$name" grant location com.atlasbound.app || true
}

build_tests() {
  local name="$1"
  local dest="platform=iOS Simulator,name=${name}"
  xcodebuild build-for-testing \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$dest" \
    COMPILER_INDEX_STORE_ENABLE=NO
}

run_tests() {
  local name="$1"
  shift
  local dest="platform=iOS Simulator,name=${name}"
  rm -rf "$RESULT_BUNDLE"
  xcodebuild test-without-building \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$dest" \
    -resultBundlePath "$RESULT_BUNDLE" \
    COMPILER_INDEX_STORE_ENABLE=NO \
    "$@"
}

main() {
  SIMULATOR_NAME="$(resolve_simulator)"
  echo "Using simulator: ${SIMULATOR_NAME}"

  bootstrap_snapshots_if_needed
  start_simulator "$SIMULATOR_NAME"
  build_tests "$SIMULATOR_NAME"
  prepare_simulator "$SIMULATOR_NAME"
  run_tests "$SIMULATOR_NAME" "$@"
}

main "$@"
