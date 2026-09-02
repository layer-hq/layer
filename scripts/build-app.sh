#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: Layer is a native macOS app and must be built on macOS." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
APP_DIR="$BUILD_DIR/Layer.app"
CONTENTS_DIR="$APP_DIR/Contents"
CONFIGURATION="${CONFIGURATION:-release}"

if [[ "$CONFIGURATION" != "debug" && "$CONFIGURATION" != "release" ]]; then
  echo "error: CONFIGURATION must be 'debug' or 'release'." >&2
  exit 1
fi

swift build --package-path "$ROOT_DIR" --triple arm64-apple-macosx -c "$CONFIGURATION"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources" "$CONTENTS_DIR/Frameworks"
cp "$BUILD_DIR/$CONFIGURATION/Layer" "$CONTENTS_DIR/MacOS/Layer"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/Layer.icns" "$CONTENTS_DIR/Resources/Layer.icns"

WEBRTC_FRAMEWORK="$BUILD_DIR/$CONFIGURATION/WebRTC.framework"
if [[ -d "$WEBRTC_FRAMEWORK" ]]; then
  cp -R "$WEBRTC_FRAMEWORK" "$CONTENTS_DIR/Frameworks/"
  install_name_tool \
    -add_rpath "@executable_path/../Frameworks" \
    "$CONTENTS_DIR/MacOS/Layer"
fi

RESOURCE_BUNDLE="$BUILD_DIR/$CONFIGURATION/Layer_Layer.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  # Nested bundles belong in Contents/Resources so the outer application can
  # be sealed and verified by codesign.
  cp -R "$RESOURCE_BUNDLE" "$CONTENTS_DIR/Resources/"
fi

# A stable identity lets Screen Recording permission survive rebuilds.
SIGNING_IDENTITY="${SIGNING_IDENTITY:-$(
  security find-identity -v -p codesigning |
    awk -F'"' '/Developer ID Application:/ { print $2; exit }'
)}"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "warning: no Developer ID identity found; using ad-hoc signing." >&2
  SIGNING_IDENTITY="-"
fi

if [[ -d "$CONTENTS_DIR/Frameworks/WebRTC.framework" ]]; then
  codesign \
    --force \
    --options runtime \
    --sign "$SIGNING_IDENTITY" \
    "$CONTENTS_DIR/Frameworks/WebRTC.framework"
fi

codesign \
  --force \
  --options runtime \
  --entitlements "$ROOT_DIR/Resources/Layer.entitlements" \
  --sign "$SIGNING_IDENTITY" \
  "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "Built $APP_DIR"
