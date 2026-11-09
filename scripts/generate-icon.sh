#!/usr/bin/env bash
# Regenerates Resources/AppIcon/AppIcon-1024.png and Resources/AppIcon.icns from scripts/generate-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
SDK_ARGS=()
[[ -n "${SDKROOT:-}" ]] && SDK_ARGS=(-sdk "$SDKROOT")
xcrun swiftc ${SDK_ARGS[@]+"${SDK_ARGS[@]}"} scripts/generate-icon.swift -o "$TMP/generate-icon"
"$TMP/generate-icon" Resources/AppIcon/AppIcon-1024.png
ICONSET="$TMP/AppIcon.iconset"; mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/AppIcon/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size*2)) $((size*2)) Resources/AppIcon/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "✓ Resources/AppIcon.icns"
