#!/usr/bin/env bash
set -euo pipefail

# Fails if Sources/Layer line coverage is below THRESHOLD percent.
# Requires: swift test --enable-code-coverage

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

THRESHOLD="${COVERAGE_MIN:-70}"
BIN_PATH="$(swift build --show-bin-path)"
PROFDATA="$BIN_PATH/codecov/default.profdata"
BIN="$BIN_PATH/LayerPackageTests.xctest/Contents/MacOS/LayerPackageTests"

if [[ ! -x "$BIN" || ! -f "$PROFDATA" ]]; then
  echo "error: coverage artifacts missing. Run: swift test --enable-code-coverage" >&2
  exit 1
fi

REPORT="$(xcrun llvm-cov report "$BIN" \
  -instr-profile="$PROFDATA" \
  -ignore-filename-regex='Tests/|\.build/' \
  Sources/Layer)"

echo "$REPORT"
echo

# llvm-cov's TOTAL line has three Cover columns (regions, lines, branches).
# Field 10 is line coverage; the last field is branch coverage, often "-".
PCT="$(awk '/^TOTAL/ { gsub(/%/, "", $10); print $10 }' <<<"$REPORT")"

if [[ -z "$PCT" ]]; then
  echo "error: could not parse line coverage from llvm-cov report." >&2
  exit 1
fi

if awk -v p="$PCT" -v t="$THRESHOLD" 'BEGIN { exit (p+0 >= t) ? 0 : 1 }'; then
  echo "Line coverage ${PCT}% meets the ${THRESHOLD}% minimum."
else
  echo "error: line coverage ${PCT}% is below ${THRESHOLD}%." >&2
  exit 1
fi
