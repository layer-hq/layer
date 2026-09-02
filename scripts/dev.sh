#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v fswatch >/dev/null 2>&1; then
  echo "error: make dev requires fswatch (install it with: brew install fswatch)." >&2
  exit 1
fi

run_app() {
  if ! make -C "$ROOT_DIR" CONFIGURATION=debug run; then
    echo "Build failed; watching for the next change..." >&2
  fi
}

run_app
echo "Watching for changes. Press Ctrl-C to stop."

fswatch -o --latency 0.2 \
  "$ROOT_DIR/Sources" \
  "$ROOT_DIR/Resources" \
  "$ROOT_DIR/Package.swift" \
  "$ROOT_DIR/scripts/build-app.sh" |
while read -r _; do
  run_app
done
