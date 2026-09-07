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
cp "$ROOT_DIR/LICENSE" "$CONTENTS_DIR/Resources/"
cp "$ROOT_DIR/THIRD-PARTY-NOTICES.md" "$CONTENTS_DIR/Resources/"

SPARKLE_SOURCE="$BUILD_DIR/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
SPARKLE_DEST="$CONTENTS_DIR/Frameworks/Sparkle.framework"
if [[ ! -d "$SPARKLE_SOURCE" ]]; then
  echo "error: Sparkle.framework not found" >&2
  exit 1
fi
cp -a "$SPARKLE_SOURCE" "$SPARKLE_DEST"
rm -rf "$SPARKLE_DEST/Versions/B/XPCServices" "$SPARKLE_DEST/XPCServices"

WEBRTC_FRAMEWORK="$BUILD_DIR/$CONFIGURATION/WebRTC.framework"
if [[ -d "$WEBRTC_FRAMEWORK" ]]; then
  cp -R "$WEBRTC_FRAMEWORK" "$CONTENTS_DIR/Frameworks/"
fi

RESOURCE_BUNDLE="$BUILD_DIR/$CONFIGURATION/Layer_Layer.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  # Nested bundles belong in Contents/Resources so the outer application can
  # be sealed and verified by codesign.
  cp -R "$RESOURCE_BUNDLE" "$CONTENTS_DIR/Resources/"
fi

if ! otool -l "$CONTENTS_DIR/MacOS/Layer" | grep -q "@executable_path/../Frameworks"; then
  install_name_tool \
    -add_rpath "@executable_path/../Frameworks" \
    "$CONTENTS_DIR/MacOS/Layer"
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

SIGN_FLAGS=(--force --sign "$SIGNING_IDENTITY")
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  SIGN_FLAGS+=(--options runtime --timestamp)
fi

codesign "${SIGN_FLAGS[@]}" "$SPARKLE_DEST/Versions/B/Autoupdate"
codesign "${SIGN_FLAGS[@]}" "$SPARKLE_DEST/Versions/B/Updater.app"
codesign "${SIGN_FLAGS[@]}" "$SPARKLE_DEST"

if [[ -d "$CONTENTS_DIR/Frameworks/WebRTC.framework" ]]; then
  codesign "${SIGN_FLAGS[@]}" "$CONTENTS_DIR/Frameworks/WebRTC.framework"
fi

codesign "${SIGN_FLAGS[@]}" \
  --entitlements "$ROOT_DIR/Resources/Layer.entitlements" \
  "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "Built $APP_DIR"
