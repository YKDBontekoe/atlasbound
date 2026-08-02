#!/usr/bin/env bash
# Build and/or run iOS tests for CI and local parity.
#
# CI_TEST_MODE:
#   all   (default) — build-for-testing then test-without-building (local)
#   build — compile once and write portable test products
#   test  — boot simulator and run from existing test products
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="${SCHEME:-Atlasbound}"
PROJECT="${PROJECT:-Atlasbound.xcodeproj}"
RESULT_BUNDLE="${RESULT_BUNDLE:-TestResults.xcresult}"
SIMULATOR_NAME="${SIMULATOR_NAME:-}"
CI_TEST_MODE="${CI_TEST_MODE:-all}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-build/TestDerivedData}"
TEST_PRODUCTS_PATH="${TEST_PRODUCTS_PATH:-dist/Atlasbound.xctestproducts}"
XCTESTRUN_PATH="${XCTESTRUN_PATH:-dist/Atlasbound.xctestrun}"

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

destination_for() {
  local name="$1"
  echo "platform=iOS Simulator,name=${name}"
}

ensure_parent_dir() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
}

find_xctestrun() {
  local products_dir="${DERIVED_DATA_PATH}/Build/Products"
  if [[ ! -d "$products_dir" ]]; then
    return 1
  fi
  # Prefer the newest scheme-named xctestrun under Build/Products.
  find "$products_dir" -maxdepth 1 -name "*.xctestrun" -print \
    | sort \
    | tail -1
}

stage_xctestrun_products() {
  # Fallback when -testProductsPath is unavailable: copy Products (including
  # the .xctestrun) so __TESTROOT__ stays the Products directory.
  local xctestrun
  xctestrun="$(find_xctestrun || true)"
  if [[ -z "$xctestrun" ]]; then
    echo "No .xctestrun found under ${DERIVED_DATA_PATH}/Build/Products" >&2
    return 1
  fi

  rm -rf dist/TestProducts
  mkdir -p dist/TestProducts
  cp -R "${DERIVED_DATA_PATH}/Build/Products/." dist/TestProducts/
  local staged
  staged="$(find dist/TestProducts -maxdepth 1 -name '*.xctestrun' -print | sort | tail -1)"
  if [[ -z "$staged" ]]; then
    echo "Failed to stage xctestrun under dist/TestProducts" >&2
    return 1
  fi
  # Stable path for CI unpack / env wiring.
  XCTESTRUN_PATH="$staged"
  export XCTESTRUN_PATH
  # Also write a pointer file so unpack can rediscover without DerivedData.
  printf '%s\n' "$(basename "$staged")" > dist/TestProducts/.xctestrun-name
  echo "Staged xctestrun fallback at ${XCTESTRUN_PATH}"
}

build_tests() {
  local name="$1"
  local dest
  dest="$(destination_for "$name")"
  ensure_parent_dir "$TEST_PRODUCTS_PATH"
  mkdir -p "$DERIVED_DATA_PATH"
  rm -rf "$TEST_PRODUCTS_PATH" "$XCTESTRUN_PATH" dist/TestProducts

  echo "Building for testing (derivedData=${DERIVED_DATA_PATH})"
  # Prefer portable .xctestproducts (Xcode 16+). Some toolchains reject mixing
  # -testProductsPath with -project; fall back to Products + .xctestrun.
  if xcodebuild build-for-testing \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -destination "$dest" \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      -testProductsPath "$TEST_PRODUCTS_PATH" \
      COMPILER_INDEX_STORE_ENABLE=NO; then
    if [[ -e "$TEST_PRODUCTS_PATH" ]]; then
      echo "Test products ready at ${TEST_PRODUCTS_PATH}"
      return 0
    fi
  else
    echo "build-for-testing with -testProductsPath failed; retrying without it" >&2
  fi

  xcodebuild build-for-testing \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$dest" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    COMPILER_INDEX_STORE_ENABLE=NO
  stage_xctestrun_products
}

run_tests_from_products() {
  local name="$1"
  shift
  local dest
  dest="$(destination_for "$name")"
  rm -rf "$RESULT_BUNDLE"

  if [[ -e "$TEST_PRODUCTS_PATH" ]]; then
    echo "Testing without building ← ${TEST_PRODUCTS_PATH}"
    xcodebuild test-without-building \
      -testProductsPath "$TEST_PRODUCTS_PATH" \
      -destination "$dest" \
      -resultBundlePath "$RESULT_BUNDLE" \
      COMPILER_INDEX_STORE_ENABLE=NO \
      "$@"
    return
  fi

  local xctestrun="$XCTESTRUN_PATH"
  if [[ ! -f "$xctestrun" && -f dist/TestProducts/.xctestrun-name ]]; then
    xctestrun="dist/TestProducts/$(tr -d '\n' < dist/TestProducts/.xctestrun-name)"
  fi
  if [[ ! -f "$xctestrun" ]]; then
    xctestrun="$(find dist/TestProducts -maxdepth 1 -name '*.xctestrun' -print 2>/dev/null | sort | tail -1 || true)"
  fi
  if [[ -n "$xctestrun" && -f "$xctestrun" ]]; then
    echo "Testing without building ← ${xctestrun}"
    xcodebuild test-without-building \
      -xctestrun "$xctestrun" \
      -destination "$dest" \
      -resultBundlePath "$RESULT_BUNDLE" \
      COMPILER_INDEX_STORE_ENABLE=NO \
      "$@"
    return
  fi

  echo "Missing test products at ${TEST_PRODUCTS_PATH} and xctestrun under dist/TestProducts" >&2
  exit 1
}

run_tests_scheme() {
  local name="$1"
  shift
  local dest
  dest="$(destination_for "$name")"
  rm -rf "$RESULT_BUNDLE"
  xcodebuild test-without-building \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$dest" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -resultBundlePath "$RESULT_BUNDLE" \
    COMPILER_INDEX_STORE_ENABLE=NO \
    "$@"
}

usage() {
  cat <<'EOF' >&2
Usage: CI_TEST_MODE=all|build|test ./scripts/ci-run-tests.sh [xcodebuild -only-testing: args...]

Environment:
  CI_TEST_MODE          all (default), build, or test
  TEST_PRODUCTS_PATH    portable .xctestproducts path (default: dist/Atlasbound.xctestproducts)
  XCTESTRUN_PATH        fallback .xctestrun path (default: dist/Atlasbound.xctestrun)
  DERIVED_DATA_PATH     derived data for compile (default: build/TestDerivedData)
  RESULT_BUNDLE         xcresult path (default: TestResults.xcresult)
  SIMULATOR_NAME        override preferred iPhone simulator
EOF
}

main() {
  case "$CI_TEST_MODE" in
    all|build|test) ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown CI_TEST_MODE=${CI_TEST_MODE}" >&2
      usage
      exit 1
      ;;
  esac

  SIMULATOR_NAME="$(resolve_simulator)"
  echo "Using simulator: ${SIMULATOR_NAME}"
  echo "CI_TEST_MODE=${CI_TEST_MODE}"

  case "$CI_TEST_MODE" in
    build)
      # Compile only — simulator need not be booted for build-for-testing.
      build_tests "$SIMULATOR_NAME"
      ;;
    test)
      bootstrap_snapshots_if_needed
      start_simulator "$SIMULATOR_NAME"
      prepare_simulator "$SIMULATOR_NAME"
      run_tests_from_products "$SIMULATOR_NAME" "$@"
      ;;
    all)
      bootstrap_snapshots_if_needed
      start_simulator "$SIMULATOR_NAME"
      build_tests "$SIMULATOR_NAME"
      prepare_simulator "$SIMULATOR_NAME"
      if [[ -e "$TEST_PRODUCTS_PATH" || -f "$XCTESTRUN_PATH" ]]; then
        run_tests_from_products "$SIMULATOR_NAME" "$@"
      else
        run_tests_scheme "$SIMULATOR_NAME" "$@"
      fi
      ;;
  esac
}

main "$@"
