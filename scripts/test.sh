#!/usr/bin/env bash
# Runs QuickDock's automated tests.
#
# With only the Command Line Tools installed, the Swift Testing macro plugin lives
# in a subdirectory the compiler does not search by default, so we pass it explicitly.
# With full Xcode this is not needed and the flag is skipped.
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=select-sdk.sh
source scripts/select-sdk.sh

EXTRA=()
DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
PLUGIN_DIR="$DEV_DIR/usr/lib/swift/host/plugins/testing"
if [[ "$DEV_DIR" == *CommandLineTools* && -d "$PLUGIN_DIR" ]]; then
  EXTRA=(-Xswiftc -plugin-path -Xswiftc "$PLUGIN_DIR")
fi

swift test ${EXTRA[@]+"${EXTRA[@]}"} "$@"
