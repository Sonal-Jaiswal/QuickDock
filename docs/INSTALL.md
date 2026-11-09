# Installing QuickDock

QuickDock 0.9.x is an **unsigned early-access build**. It is not signed with an Apple Developer ID
certificate and has not been notarized by Apple, so it is **not Apple-verified**. macOS (Gatekeeper)
blocks apps like this the first time they are opened. This guide shows how to allow QuickDock — and only
QuickDock — once. You should never disable Gatekeeper for your whole Mac.

## 1. Download

- Download `QuickDock-<version>-arm64.dmg` **only** from the project's official GitHub Releases page.
- Optional but recommended — verify the checksum in Terminal and compare it with the `.sha256` file on the release page:

  ```sh
  shasum -a 256 ~/Downloads/QuickDock-0.9.2-arm64.dmg
  ```

## 2. Install

1. Double-click the DMG to open it.
2. Drag **QuickDock** onto the **Applications** shortcut.
3. Eject the disk image (drag it to the Trash or click ⏏ in Finder's sidebar).

## 3. First launch

### macOS 15 Sequoia, macOS 26 and later
1. Open QuickDock from Applications. macOS says it can't verify that QuickDock is free of malware. Click **Done**. Don't choose Move to Trash.
2. Open **System Settings › Privacy & Security**.
3. Scroll to **Security**, find the message about QuickDock and click **Open Anyway**.
4. Authenticate with your password or Touch ID, then click **Open Anyway** in the final dialog.

The **Open Anyway** button only appears after you've tried to open the app, and only for a limited time.
If it isn't there, open QuickDock once more and come straight back.

### macOS 13 Ventura and macOS 14 Sonoma
1. In Finder, open **Applications**.
2. Control-click (or right-click) **QuickDock** and choose **Open**.
3. Click **Open** in the dialog.

(The Privacy & Security › Open Anyway route works on these versions too.)

After this one-time approval QuickDock opens normally. It lives in the **menu bar**, not the Dock:
look for its icon near the clock, or press **⌥ Space**.

## Troubleshooting

| Problem | What to do |
| --- | --- |
| “QuickDock is damaged and can't be opened” | Delete the download, download it again from GitHub Releases and verify the checksum. Don't run Terminal commands from websites that promise to “fix” this. |
| No “Open Anyway” button | Try opening QuickDock first, then go to Privacy & Security within the hour. |
| Can't see the menu-bar icon | On Macs with a notch, extra menu-bar icons can be hidden. Press ⌥Space, or quit some menu-bar apps. |
| Shortcut doesn't work | Another app may use it. Open Settings › Shortcuts. It shows whether the shortcut is active, and lets you record another. |
| An item has an orange badge | The file moved or was deleted, or the app was uninstalled. Click it and choose **Locate…** or **Remove**. |
| Several files say “Needs access” | Settings › Data › **Restore File Access**: choose a folder that contains them (e.g. your Home folder). |
| Open at Login needs approval | Allow QuickDock in System Settings › General › Login Items. |

## Advanced: removing the quarantine flag

If you are comfortable with Terminal and have verified the checksum, you can clear the download
quarantine flag for this one app instead of using Open Anyway:

```sh
xattr -d com.apple.quarantine /Applications/QuickDock.app
```

This affects only QuickDock. Do **not** use `spctl --master-disable` or other commands that turn off
Gatekeeper for everything.
