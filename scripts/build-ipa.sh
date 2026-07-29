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

mkdir -p "$OUTPUT_DIR" "$(dirname "$ARCHIVE_PATH")"

VERSION_FLAGS=()
if [[ -n "$MARKETING_VERSION" ]]; then
  VERSION_FLAGS+=("MARKETING_VERSION=${MARKETING_VERSION}")
fi
if [[ -n "$BUILD_NUMBER" ]]; then
  VERSION_FLAGS+=("CURRENT_PROJECT_VERSION=${BUILD_NUMBER}")
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
  "${VERSION_FLAGS[@]}"

APP_PATH="$ARCHIVE_PATH/Products/Applications/${SCHEME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: expected app bundle at $APP_PATH" >&2
  exit 1
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
