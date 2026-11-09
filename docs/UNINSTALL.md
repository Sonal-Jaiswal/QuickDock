# Uninstalling QuickDock

QuickDock installs no helpers, daemons, kernel or system extensions. Removing it takes a minute.

## Steps

1. **Turn off Open at Login** (if you enabled it): QuickDock Settings › General. You can also remove it later in
   System Settings › General › Login Items.
2. **Quit QuickDock:** right-click its menu-bar icon › **Quit QuickDock**.
3. **Delete the app:** drag `/Applications/QuickDock.app` to the Trash.
4. **Optional — delete your data:** in Finder choose **Go › Go to Folder…**, enter
   `~/Library/Containers/` and move **`io.github.sonal-jaiswal.QuickDock`** to the Trash.
   This folder holds your items (`library.json`, its backup), custom icons and preferences.

Consider **Settings › Data › Export Configuration…** first if you might come back.

> macOS protects app containers: Terminal commands (including `scripts/uninstall.sh`) can delete everything
> inside QuickDock's container but not the container folder itself, which then stays empty. Removing it in
> Finder works.

## Scripted

From a clone of the repository:

```sh
scripts/uninstall.sh              # removes the app, then asks before deleting data
scripts/uninstall.sh --keep-data  # removes only the app
```
