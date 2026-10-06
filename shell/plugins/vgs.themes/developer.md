# Themes developer reference

## Capabilities

`theme`: list packages, read the catalog, install a catalog package, apply a package, list and set images, download or update wallpapers, and fetch a selected catalog preview.

`surfaces`: open the panel and the full-screen browser, and close them from their own controls.

`shortcut`: register `vgs.themes:themes`, `vgs.themes:wallpapers`, `vgs.themes:panel` and `vgs.themes:gaps`, which the manifest binds to `SUPER+T`, `SUPER+W`, `SUPER+CTRL+J` and `SUPER+SHIFT+BACKSPACE`. The manifest's `menu` rows open the first two and the last from the launcher.

`configure`: write the No window gaps setting when its toggle runs.

`ipc`: the `gaps` function, the same toggle over IPC.

`screens`: count the monitors for the wallpaper browser's monitor choice, and name the monitor it shows on.

The generated Hyprland layer captures the keyboard while a full-screen browser is open, so a user window bind on the same keys does not reach the windows behind it. The user's Hyprland directional focus keys move through the cards while a browser is open.

## Settings keys

The settings sit on the plugin's row in `plugins` in `~/.config/vgshell/shell.json`, for example `{ "id": "vgs.themes", "placement": "top-right" }`.

`placement`: where the panel opens, one of `top-left`, `top`, `top-right`, `left`, `center`, `right`, `bottom-left`, `bottom` and `bottom-right`. Default `top-right`. A summon of the panel over IPC opens it at the same place:

```text
vgshell ipc call shell summon panel vgs.themes '{}'
```

`noWindowGaps`: no gaps around or between tiled windows on any workspace, which the Hyprland layer writes as a workspace rule ([hyprland.md](../../../docs/architecture/hyprland.md)). The launcher's gaps row and its shortcut flip it. A theme carries no gaps, so applying another theme leaves it as it is. Default `false`. The same toggle over IPC:

```text
vgshell ipc call vgs.themes invoke gaps ''
```

`setWindowBorders`: whether themes set Hyprland border colours, border thickness and shadow colour over the user's own Hyprland lines. Default `true`.

`setCornerRadius`: whether themes set Hyprland window radius, rounding power and grouped-window tab radius over the user's own Hyprland lines. Default `true`.

`setWindowAnimations`: whether themes set Hyprland window, layer, workspace and fade animation presets over the user's own Hyprland lines. Default `false`.

## Apply

A click on a panel row applies that package, as `bin/vgshell theme apply <name>` does. Closing the panel does not stop an apply. The panel shows the result when it opens again.

The panel keeps the last apply's problems on its package's row until the next apply: each application target that failed, with its reason, and each file of an installed package the apply dropped because its target runs code, which `bin/vgshell theme apply` reports as `dropped=`.

The Modified badge shows while `~/.config/vgshell/theme.json` no longer matches the package it names.

Add from URL at the foot of the panel opens the floating TUI for `bin/vgshell theme add`, asks for a git URL, then offers to apply the new theme.

A catalog row shows Installing while an install runs, and the browser's progress text while a wallpaper download runs. Alt+D in the panel runs the selected installed catalog row's Download wallpapers action when it is shown. When the applied catalog theme's wallpapers are missing, or the catalog has newer ones, the wallpaper browser's Theme list ends with a Download or Update card. Enter on it downloads them with progress, applies the theme again so its wallpaper shows, and keeps the browser open.

## Wallpapers

The applied package's wallpaper is the package's remembered image, else the first of its `backgrounds/` directory in name order. A package without images draws nothing, so a wallpaper another program draws shows. The image is cropped to fill each screen.

The panel's Previous and Next buttons show the package's previous or next image and remember it for the package, as `bin/vgshell theme background previous` and `next` do. Applying the package again shows the remembered image.

A monitor shows its own image once `bin/vgshell theme background set <path> --screen <output>` names it, and every other monitor keeps the current image. `--every-screen` in place of `--screen` shows the image on every monitor and clears each monitor's own image. A monitor whose own image was deleted shows the current image. The next apply of a package clears every monitor's own image. The wallpaper browser's All monitors and This monitor controls do the same: each open starts on All monitors.

`~/.local/state/vgshell/background` links to the same image, for a lock screen or any other application that draws it.

## Browser cards

A package `preview.png` draws first on a card. Without it, the selected card draws a live desktop preview from the package's tokens and terminal colours. Side cards draw the package preview, wallpaper or palette.

In the theme browser, typing filters by package name or label. When no theme matches, Clear filter clears the filter, as Esc does. In the wallpaper browser, Alt+S, as a click on the source line under the rail does, switches between the applied theme's wallpapers and every wallpaper, Alt+M between All monitors and This monitor, and Space sets the selected wallpaper or runs the Download or Update card. Tab, Shift+Tab, Ctrl+Tab, Ctrl+Shift+Tab, Ctrl+PageDown and Ctrl+PageUp switch between the two browsers.

## Browser theming

Chromium, Google Chrome, Microsoft Edge and Brave take the theme's background colour through a managed policy. The Arch and Fedora packages install its writer for every user. A home install sets the writer up once through the Install browser theming action, the `browser-policy` TUI, which opens a floating terminal where sudo asks for the password. The `browserTheming` status reports whether the writer is there. [theme-targets.md](../../../docs/architecture/theme-targets.md) holds the targets.
