# Changelog

All notable changes to QuickDock are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and QuickDock uses [Semantic Versioning](https://semver.org/).

## [0.9.2] - 2026-11-10

### Changed
- The Quick Wheel shortcut is now **⌃⌥Tab** (Control-Option-Tab). Current macOS doesn't pass plain ⌥Tab to apps, so the wheel never opened. If you were on ⌥Tab, you're moved to ⌃⌥Tab automatically, and the shortcut recorder now explains why ⌥Tab can't be used. The launcher stays on ⌥Space.

## [0.9.1] - 2026-11-09

### Fixed
- Quick Wheel: the hold now follows the ⌥ key, not Tab. Before, letting Tab up a moment late closed the wheel, letting go of ⌥ didn't open the chosen app, and tapping Tab again to cycle closed the wheel.
- The wheel's buttons no longer take keyboard focus, so pressing Space can't clear the clipboard history by accident.

## [0.9.0] - 2026-11-09

First public early-access build (unsigned, not notarized).

### Added
- Quick Wheel: hold ⌥Tab and a ring of your favorite and most-used apps appears around the pointer. Flick and release to open or switch, tap to click, press Tab again to cycle, or press 1–9.
- Optional clipboard history beside the wheel. It's text only, stays on your Mac, skips password-manager copies, supports pinning, and saves to disk only if you choose.
- "Support QuickDock" link in About, pointing to GitHub Sponsors (donations are optional).
- Floating launcher panel with Liquid Glass on macOS 26 and later, centred on the display with the pointer.
- Menu-bar icon: click to open the launcher, right-click for favorites, adding items, Settings and Quit.
- Global keyboard shortcut (default ⌥Space) with conflict detection, automatic fallback and a shortcut recorder.
- Apps, files, folders, websites and built-in actions: copy a text snippet, new email, Mission Control, Screenshot, Screen Saver, System Settings.
- Instant search, type filters, favorites, categories, custom names and custom icons (SF Symbols or images).
- Drag-and-drop reordering, plus adding by dropping files and links onto the launcher or the app icon.
- Keyboard navigation: arrow keys, Return, ⌘Return, ⌘1–⌘9, Tab, ⌘E, ⌘D and Escape.
- Clear states for missing files and uninstalled apps, with Locate… and Remove.
- Settings: General, Appearance, Launcher, Shortcuts, Organization, Data and About.
- Configuration export and import (merge or replace) with validation, plus Restore File Access.
- Optional Open at Login.
- First-launch onboarding.
- App Sandbox with no network access. Security-scoped bookmarks keep access to the files you choose.
