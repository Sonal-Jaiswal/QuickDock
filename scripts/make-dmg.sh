#!/usr/bin/env bash
# Packages build/QuickDock.app into a compressed DMG in ./dist, with a SHA-256 checksum.
#
#   scripts/build-app.sh && scripts/make-dmg.sh
#   SIGN_IDENTITY="Developer ID Application: …" scripts/make-dmg.sh   # also signs the DMG
#
# Output: dist/QuickDock-<version>-arm64.dmg and dist/QuickDock-<version>-arm64.dmg.sha256
set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=../config/release.env
source config/release.env
VERSION="$(tr -d '[:space:]' < VERSION)"
APP="build/QuickDock.app"
ARCH_LABEL="${ARCH_LABEL:-arm64}"
NAME="QuickDock-${VERSION}-${ARCH_LABEL}"
DMG="dist/${NAME}.dmg"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

[[ -d "$APP" ]] || { echo "error: $APP not found. Run scripts/build-app.sh first." >&2; exit 1; }
codesign --verify --strict "$APP"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/QuickDock.app"
ln -s /Applications "$STAGING/Applications"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  cat > "$STAGING/Read Me First.txt" <<EOF
QuickDock ${VERSION} — early access build
==========================================

INSTALL
1. Drag QuickDock into the Applications folder.
2. Eject this disk image.
3. Open QuickDock from Applications.

THIS BUILD IS NOT SIGNED OR NOTARIZED
QuickDock is an independent project without an Apple Developer ID yet, so this
build is not signed with a Developer ID certificate and has not been notarized by
Apple. macOS will warn you the first time you open it.

To open it (macOS 15 Sequoia and later):
  1. Open QuickDock. When macOS says it can't verify the app, click Done.
  2. Open System Settings › Privacy & Security.
  3. Scroll to Security and click "Open Anyway" next to QuickDock.
  4. Confirm with your password, then click Open.

On macOS 13 Ventura and 14 Sonoma you can also Control-click QuickDock in
Applications, choose Open, then click Open in the dialog.

You only need to do this once. Never disable Gatekeeper for your whole Mac.
Only install QuickDock downloaded from its official GitHub Releases page, and
compare the SHA-256 checksum published there.

UNINSTALL
Quit QuickDock (menu-bar icon › right-click › Quit), drag it from Applications to
the Trash, and optionally delete:
  ~/Library/Containers/${BUNDLE_ID}
(QuickDock's items and settings). Or run the uninstall script from the
QuickDock repository: scripts/uninstall.sh
EOF
fi

mkdir -p dist
rm -f "$DMG" "$DMG.sha256"
hdiutil create -volname "QuickDock ${VERSION}" -srcfolder "$STAGING" -fs HFS+ -format UDZO \
  -imagekey zlib-level=9 -ov "$DMG" >/dev/null

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi

hdiutil verify "$DMG" >/dev/null
(cd dist && shasum -a 256 "${NAME}.dmg" > "${NAME}.dmg.sha256")
echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
cat "$DMG.sha256"
