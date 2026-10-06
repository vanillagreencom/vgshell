# Scratchpads developer reference

The service registers the shortcut `vgs.scratchpads:pad-<name>` for each pad, with no default key.

The setting is `pads`, a list of `{ name, command, class, width, height, position, margin, entry, motion, screen, preload }` in the plugin's `plugins[]` row.

The manifest's `hyprland.pads` names `pads`: the core writes each pad's window rule and the toggle the service sends ([docs/architecture/hyprland.md](../../../docs/architecture/hyprland.md)).

The status entries are `shown`, which pad each screen shows, and `screens`, the screen choices.

The service registers each pad's shortcut and follows each pad's window from Hyprland's `openwindow` and `closewindow` events. A press sends `shell.compositor.togglePad`. When the layer answers that the pad's workspace holds no window, the service moves a known window that left it back in, or runs the app with `sh -c` and sends the toggle once Hyprland reports a window of the pad's class, if the user still wants the pad then. More presses during the start change that wish. When the layer answers that it holds no such pad, as for a pad whose class another pad uses, the service starts nothing and shows a message. The `background` instance on each screen is shown only while a pad is shown there; it draws nothing and hides the pad on a press. The layer moves a window no pad holds any more to the focused workspace each time it loads. Why a pad is tiled in its own special workspace is in [hyprland.md § Configuration layer](../../../docs/architecture/hyprland.md#configuration-layer).

Hyprland has one animation for every hidden workspace it shows. A pad sets it each time it shows or hides, so a hidden workspace of the user's own moves the way the last pad did, until Hyprland reloads its settings.

A pad is sized inside its screen's free area. A `dwindle:special_scale_factor` below 1 in the user's Hyprland settings makes every pad smaller than its size.

While a pad is shown, the desktop behind the windows on its screen shows the theme's background colour when the Themes plugin draws no wallpaper there.

`scripts/smoke/rows/scratchpads.sh` is the validation row. It makes pads from the Plugins window in the nested sandbox and types the key on the nested seat. It reads a second pad on the first one's class reported, the pad never shown empty while its slow app starts, the pad at its shares and anchor at three output modes and after a mode change, bursts of presses toggling it once each, a window moved out coming back, a setting change taking effect on the next press, a press beside the pad or a focus move hiding it, an app that opens no window ending in one message, a restarted shell starting no second app, and the pad's window brought to the focused workspace when the plugin is turned off or the pad removed. Its controls read an empty pad, a background that takes no press, a layer with no gaps, and a layer with no focus hook and no refit.
