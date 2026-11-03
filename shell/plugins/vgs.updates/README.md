# Updates

Updates checks your system, VGS, plugins, themes and developer tools for updates, and installs them. Its bar icon shows how many wait.

![The Updates window with its System row open](../../../docs/images/plugins/vgs.updates-window.webp)

## Features

- Checks system packages, AUR packages, verified packages such as gliff, Flatpak apps, mise tools, VGS itself, installed plugins and installed themes.
- A bar icon with the count of waiting updates, and a warning when a check fails.
- A window on `SUPER+CTRL+U` or a click on the icon, with one row per source. Update installs one source, and Update everything installs all of them.
- Open last log shows the log of the last update run.
- A system snapshot with Snapper or Timeshift before an update, when one is installed.
- An optional AI review of each package before it installs. A flagged package lets you skip it or install it anyway. Package review settings opens General > Packages in System Settings.

## Setup

| Setting | What it changes |
| --- | --- |
| Check interval | Time between automatic update checks, 1 to 48 hours. |
| Hide when up to date | Hides the bar icon when a recent check finds no updates. |
| AUR command | How AUR packages update: Automatic, or a paru or yay command of your own. |
| System snapshot | Saves a system snapshot before updates when a snapshot tool is available. |
| Trust plugin and theme updates | Applies plugin and theme changes without asking first. |
| Reboot notice | On CachyOS, whether CachyOS also shows its restart notices for updates outside VGS. VGS asks once after an update that needs a restart either way. |

[developer.md](developer.md) states the checks, the bar icon and the steps of an update run.
