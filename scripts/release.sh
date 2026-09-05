#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: releases must be built on macOS." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: worktree is not clean." >&2
  exit 1
fi

IDENTITY="${SIGNING_IDENTITY:-$(
  security find-identity -v -p codesigning |
    awk -F'"' '/Developer ID Application:/ { print $2; exit }'
)}"
if [[ -z "$IDENTITY" || "$IDENTITY" == "-" ]]; then
  echo "error: no Developer ID Application identity found." >&2
  exit 1
fi

PLIST="$ROOT_DIR/Resources/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PLIST")
TAG="v$VERSION"

if [[ "$BUNDLE_ID" != "com.getlayerapp" ]]; then
  echo "error: bundle ID must be com.getlayerapp (found $BUNDLE_ID)." >&2
  exit 1
fi
if [[ ! "$BUILD" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: CFBundleVersion must be a positive integer (found $BUILD)." >&2
  exit 1
fi
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "error: tag $TAG already exists." >&2
  exit 1
fi

swift test --package-path "$ROOT_DIR"
SIGNING_IDENTITY="$IDENTITY" make build

APP="$ROOT_DIR/.build/Layer.app"
DIST="$ROOT_DIR/.build/release-dist"
DMG="$DIST/Layer-$VERSION.dmg"
STAGE="$(mktemp -d)"
MOUNT=""

cleanup() {
  if [[ -n "$MOUNT" ]]; then
    hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
  fi
  rm -rf "$STAGE"
}
trap cleanup EXIT

rm -rf "$DIST"
mkdir -p "$DIST"
cp -a "$APP" "$STAGE/Layer.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -ov -format UDZO -volname Layer \
  -srcfolder "$STAGE" "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

xcrun notarytool submit "$DMG" \
  --keychain-profile layer-notary --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
codesign --verify --verbose=2 "$DMG"

MOUNT=$(hdiutil attach -nobrowse -readonly "$DMG" | awk 'END { print $NF }')
spctl --assess --type execute --verbose=4 "$MOUNT/Layer.app"
hdiutil detach "$MOUNT"
MOUNT=""

"$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" \
  --download-url-prefix \
  "https://github.com/layer-hq/layer/releases/download/$TAG/" \
  "$DIST"

git tag -a "$TAG" -m "Layer $VERSION"
git push origin "$TAG"
gh release create "$TAG" \
  "$DMG" "$DIST/appcast.xml" \
  --title "Layer $VERSION" \
  --generate-notes

curl -fL "https://github.com/layer-hq/layer/releases/latest/download/appcast.xml" >/dev/null
curl -fLI "https://github.com/layer-hq/layer/releases/download/$TAG/Layer-$VERSION.dmg" >/dev/null

echo "Published $TAG"
