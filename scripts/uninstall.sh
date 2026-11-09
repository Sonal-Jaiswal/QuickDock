#!/usr/bin/env bash
# Removes QuickDock and, optionally, all of its data from this Mac.
#   scripts/uninstall.sh            # asks before deleting data
#   scripts/uninstall.sh --keep-data
set -euo pipefail
cd "$(dirname "$0")/.." 2>/dev/null || true

BUNDLE_ID="io.github.sonal-jaiswal.QuickDock"
[[ -f config/release.env ]] && source config/release.env

echo "Quitting QuickDock…"
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || pkill -x QuickDock 2>/dev/null || true
sleep 1

for app in "/Applications/QuickDock.app" "$HOME/Applications/QuickDock.app"; do
  if [[ -d "$app" ]]; then
    echo "Moving $app to the Trash…"
    osascript -e "tell application \"Finder\" to delete POSIX file \"$app\"" >/dev/null 2>&1 || rm -rf "$app"
  fi
done

if [[ "${1:-}" == "--keep-data" ]]; then
  echo "Kept your QuickDock items and settings."
  exit 0
fi

read -r -p "Also delete your QuickDock items and settings? [y/N] " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
  CONTAINER="$HOME/Library/Containers/$BUNDLE_ID"
  # Removes items, icons and preferences. macOS protects the container folder itself
  # (and its system metadata file) from deletion by other apps, so that empty shell may remain.
  rm -rf "$CONTAINER" 2>/dev/null || true
  if [[ -d "$CONTAINER" ]]; then
    find "$CONTAINER" -mindepth 1 -not -name ".com.apple.containermanagerd.metadata.plist" -delete 2>/dev/null || true
    echo "Deleted QuickDock's items and settings."
    echo "macOS keeps the now-empty folder $CONTAINER."
    echo "To remove it too, open it in Finder (Go › Go to Folder…) and drag it to the Trash."
  else
    echo "Deleted QuickDock's data."
  fi
fi
echo "Done. If you enabled “Open at login”, macOS removes the login item automatically once the app is gone;"
echo "you can confirm in System Settings › General › Login Items."
