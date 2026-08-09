#!/usr/bin/env bash
# Build an unsigned IPA suitable for AltStore / SideStore (re-signed on device).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCHEME="${SCHEME:-Atlasbound}"
PROJECT="${PROJECT:-Atlasbound.xcodeproj}"
CONFIGURATION="${CONFIGURATION:-Release}"
MARKETING_VERSION="${MARKETING_VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
DERIVED_DATA="${DERIVED_DATA:-build/DerivedData}"
ARCHIVE_PATH="${ARCHIVE_PATH:-build/Atlasbound.xcarchive}"
REQUIRE_SUPABASE_CONFIG="${REQUIRE_SUPABASE_CONFIG:-false}"
REQUIRE_MAPBOX_CONFIG="${REQUIRE_MAPBOX_CONFIG:-false}"

mkdir -p "$OUTPUT_DIR" "$(dirname "$ARCHIVE_PATH")"

VERSION_FLAGS=()
if [[ -n "$MARKETING_VERSION" ]]; then
  VERSION_FLAGS+=("MARKETING_VERSION=${MARKETING_VERSION}")
fi
if [[ -n "$BUILD_NUMBER" ]]; then
  VERSION_FLAGS+=("CURRENT_PROJECT_VERSION=${BUILD_NUMBER}")
fi

# Pass the publishable key directly to xcodebuild so CI cannot accidentally
# produce a release IPA with an unresolved SUPABASE_* build setting. The key
# is safe for a public client; service-role credentials must never be used here.
SUPABASE_KEY="${SUPABASE_PUBLISHABLE_KEY:-${SUPABASE_RELEASE_PUBLISHABLE_KEY:-}}"
MAPBOX_TOKEN="${MAPBOX_PUBLIC_ACCESS_TOKEN:-${MAPBOX_RELEASE_PUBLIC_ACCESS_TOKEN:-}}"
CONFIG_FLAGS=()
if [[ -n "$SUPABASE_KEY" ]]; then
  CONFIG_FLAGS+=("SUPABASE_PUBLISHABLE_KEY=${SUPABASE_KEY}")
fi
if [[ -n "$MAPBOX_TOKEN" ]]; then
  CONFIG_FLAGS+=("MAPBOX_PUBLIC_ACCESS_TOKEN=${MAPBOX_TOKEN}")
fi

if [[ "$REQUIRE_SUPABASE_CONFIG" == "true" && -z "$SUPABASE_KEY" ]]; then
  echo "error: SUPABASE_PUBLISHABLE_KEY is required for this IPA. Set SUPABASE_RELEASE_PUBLISHABLE_KEY (or SUPABASE_PUBLISHABLE_KEY) in the build environment." >&2
  exit 1
fi
if [[ "$REQUIRE_MAPBOX_CONFIG" == "true" && -z "$MAPBOX_TOKEN" ]]; then
  echo "error: MAPBOX_PUBLIC_ACCESS_TOKEN is required for this IPA. Set MAPBOX_RELEASE_PUBLIC_ACCESS_TOKEN in the build environment." >&2
  exit 1
fi

echo "==> Archiving ${SCHEME} (${CONFIGURATION}, unsigned)"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA" \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  "${VERSION_FLAGS[@]}" \
  "${CONFIG_FLAGS[@]}"

APP_PATH="$ARCHIVE_PATH/Products/Applications/${SCHEME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: expected app bundle at $APP_PATH" >&2
  exit 1
fi

if [[ "$REQUIRE_SUPABASE_CONFIG" == "true" ]]; then
  BUILT_SUPABASE_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPABASE_PUBLISHABLE_KEY' "$APP_PATH/Info.plist" 2>/dev/null || true)"
  if [[ -z "$BUILT_SUPABASE_KEY" || "${BUILT_SUPABASE_KEY:0:2}" == '$(' || "$BUILT_SUPABASE_KEY" == *SUPABASE_* ]]; then
    echo "error: the archived IPA does not contain a resolved SUPABASE_PUBLISHABLE_KEY." >&2
    exit 1
  fi
fi

if [[ "$REQUIRE_MAPBOX_CONFIG" == "true" ]]; then
  BUILT_MAPBOX_TOKEN="$(/usr/libexec/PlistBuddy -c 'Print :MBXAccessToken' "$APP_PATH/Info.plist" 2>/dev/null || true)"
  if [[ -z "$BUILT_MAPBOX_TOKEN" || "${BUILT_MAPBOX_TOKEN:0:2}" == '$(' || "$BUILT_MAPBOX_TOKEN" == *MAPBOX_* ]]; then
    echo "error: the archived IPA does not contain a resolved MBXAccessToken." >&2
    exit 1
  fi
fi

# Prefer marketing version from the built Info.plist when not supplied.
if [[ -z "$MARKETING_VERSION" ]]; then
  MARKETING_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Info.plist")"
fi
if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Info.plist")"
fi

IPA_NAME="${SCHEME}-${MARKETING_VERSION}.ipa"
IPA_PATH="$OUTPUT_DIR/$IPA_NAME"

echo "==> Packaging $IPA_PATH"
rm -rf build/Payload
mkdir -p build/Payload
cp -R "$APP_PATH" "build/Payload/${SCHEME}.app"
(
  cd build
  rm -f "../$IPA_PATH"
  zip -qr9 "../$IPA_PATH" Payload
)

SIZE="$(stat -f%z "$IPA_PATH" 2>/dev/null || stat -c%s "$IPA_PATH")"
SHA256="$(shasum -a 256 "$IPA_PATH" | awk '{print $1}')"

{
  echo "ipa_path=$IPA_PATH"
  echo "ipa_name=$IPA_NAME"
  echo "version=$MARKETING_VERSION"
  echo "build=$BUILD_NUMBER"
  echo "size=$SIZE"
  echo "sha256=$SHA256"
} | tee "$OUTPUT_DIR/ipa-metadata.env"

echo "==> Done: $IPA_PATH ($SIZE bytes)"
