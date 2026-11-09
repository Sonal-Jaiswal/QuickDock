#!/usr/bin/env bash
# Writes website/src/config/release.json from the built DMG and CHANGELOG.md.
#   scripts/build-app.sh && scripts/make-dmg.sh && scripts/update-website-release.sh
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(tr -d '[:space:]' < VERSION)"
DMG="dist/QuickDock-${VERSION}-arm64.dmg"
[[ -f "$DMG" ]] || { echo "error: $DMG not found — run scripts/make-dmg.sh first" >&2; exit 1; }
SIZE=$(stat -f%z "$DMG")
SHA=$(cut -d' ' -f1 "$DMG.sha256")
DATE=$(awk -v v="$VERSION" '$0 ~ "^## \\[" v "\\]" { gsub(/.*- /, ""); print; exit }' CHANGELOG.md)
SIGNED=false
codesign -dv "build/QuickDock.app" 2>&1 | grep -q "Authority=Developer ID Application" && SIGNED=true
VERSION="$VERSION" DMG="$DMG" SIZE="$SIZE" SHA="$SHA" DATE="${DATE:-$(date +%F)}" SIGNED="$SIGNED" python3 - <<'PY'
import json, os, re
version = os.environ["VERSION"]
text = open("CHANGELOG.md", encoding="utf-8").read()
section = re.search(r"^## \[" + re.escape(version) + r"\][^\n]*\n(.*?)(?=^## \[|\Z)", text, re.S | re.M)
notes = [line[2:].strip() for line in (section.group(1) if section else "").splitlines() if line.startswith("- ")]
data = {
  "version": version,
  "date": os.environ["DATE"],
  "fileName": os.path.basename(os.environ["DMG"]),
  "sizeBytes": int(os.environ["SIZE"]),
  "sha256": os.environ["SHA"],
  "minimumMacOS": "macOS 13 Ventura",
  "architectures": "Apple Silicon (arm64)",
  "signed": os.environ["SIGNED"] == "true",
  "notes": notes,
}
json.dump(data, open("website/src/config/release.json", "w", encoding="utf-8"), indent=2, ensure_ascii=False)
open("website/src/config/release.json", "a").write("\n")
print(f"✓ website/src/config/release.json → {version}, {data['sizeBytes']} bytes, {len(notes)} notes, signed={data['signed']}")
PY
