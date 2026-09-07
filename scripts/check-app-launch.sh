#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EXECUTABLE="${1:-$ROOT_DIR/.build/Layer.app/Contents/MacOS/Layer}"
OUTPUT="$(/usr/bin/perl -e 'alarm 2; exec @ARGV' "$EXECUTABLE" 2>&1)" || true

if [[ "$OUTPUT" == *"Library not loaded: @rpath/WebRTC.framework/WebRTC"* ]]; then
  printf '%s\n' "$OUTPUT" >&2
  exit 1
fi

printf 'App passed the WebRTC launch check.\n'
