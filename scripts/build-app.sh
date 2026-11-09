#!/usr/bin/env bash
# Builds QuickDock.app (Release) into ./build.
#
#   scripts/build-app.sh                 # Release build, ad-hoc signed
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/build-app.sh
#   CONFIGURATION=debug scripts/build-app.sh
#   BUILD_NUMBER=42 scripts/build-app.sh
#   ARCHS="arm64 x86_64" scripts/build-app.sh   # universal (requires full Xcode)
#
# Outputs build/QuickDock.app
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# shellcheck source=../config/release.env
source config/release.env

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
CONFIGURATION="${CONFIGURATION:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ARCHS="${ARCHS:-arm64}"
APP="$ROOT/build/QuickDock.app"

# --- Choose an SDK -----------------------------------------------------------
# Command Line Tools ship without SwiftUI's macro plugin. Newer SDKs implement
# @State as a macro, so with CLT we pick the newest SDK that doesn't need it.
if [[ -z "${SDKROOT:-}" ]]; then
  DEV_DIR="$(xcode-select -p)"
  if [[ "$DEV_DIR" == *CommandLineTools* ]]; then
    for sdk in $(ls -d "$DEV_DIR"/SDKs/MacOSX[0-9]*.sdk 2>/dev/null | sort -V -r); do
      if ! grep -rqs "StateMacro" "$sdk/System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface"; then
        export SDKROOT="$sdk"
        break
      fi
    done
  fi
fi
[[ -n "${SDKROOT:-}" ]] && echo "▸ SDK: $SDKROOT"

# --- Compile -------------------------------------------------------------------
ARCH_FLAGS=()
for arch in $ARCHS; do ARCH_FLAGS+=(--arch "$arch"); done
echo "▸ Building QuickDock $VERSION ($BUILD_NUMBER), $CONFIGURATION, $ARCHS"
swift build -c "$CONFIGURATION" "${ARCH_FLAGS[@]}" --product QuickDock
BIN_DIR="$(swift build -c "$CONFIGURATION" "${ARCH_FLAGS[@]}" --show-bin-path)"

# --- Assemble the bundle -------------------------------------------------------
echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/QuickDock" "$APP/Contents/MacOS/QuickDock"
printf "APPL????" > "$APP/Contents/PkgInfo"

escape() { printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
sed -e "s|__BUNDLE_ID__|$(escape "$BUNDLE_ID")|g" \
    -e "s|__VERSION__|$(escape "$VERSION")|g" \
    -e "s|__BUILD__|$(escape "$BUILD_NUMBER")|g" \
    -e "s|__YEAR__|$(date +%Y)|g" \
    -e "s|__COPYRIGHT__|$(escape "$COPYRIGHT_HOLDER")|g" \
    -e "s|__REPO_URL__|$(escape "$REPO_URL")|g" \
    -e "s|__WEBSITE_URL__|$(escape "$WEBSITE_URL")|g" \
    -e "s|__SUPPORT_EMAIL__|$(escape "$SUPPORT_EMAIL")|g" \
    Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# App icon (.icns) from the 1024px master.
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/AppIcon/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double Resources/AppIcon/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# --- Sign ----------------------------------------------------------------------
SIGN_FLAGS=(--force --options runtime --entitlements Resources/QuickDock.entitlements --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  SIGN_FLAGS+=(--timestamp)
  echo "▸ Signing with: $SIGN_IDENTITY"
else
  echo "▸ Ad-hoc signing (unsigned build — not Developer ID signed, not notarized)"
fi
codesign "${SIGN_FLAGS[@]}" "$APP"
codesign --verify --strict --verbose=1 "$APP"

echo "✓ Built $APP"
