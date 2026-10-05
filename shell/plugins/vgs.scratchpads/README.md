# Scratchpads

Show and hide an app with one key, over whatever you work on. Each pad holds one app at the size, place and screen you set in Settings.

![The Scratchpads page in Settings](../../../docs/images/plugins/vgs.scratchpads-page.webp)

Screenshot made with `scripts/readme-shots.sh` in the nested sandbox, with the default theme at scale 2.

## Features

- Add, change and remove pads on the Scratchpads page in Settings. No file to edit.
- Give each pad its own key under Keys.
- A press starts the app when it is not running, then shows it once its window is open. An empty pad never shows.
- Set the size as a share of the screen, so one setting fits a laptop panel and a large display.
- Put the pad in the centre, at an edge or in a corner, with a margin.
- Choose the side it comes in from, and whether it slides, fades or appears at once.
- Open it on the focused screen or on one screen you choose.
- Start its app at login, so the first press shows it at once.
- Click anywhere beside the pad, or move to another window, to hide it.
- Remove a pad, or turn off Scratchpads, and its app comes to the workspace you are on.

## Settings

| Setting | What it does |
|---|---|
| App | The command that starts the app. Terminal, Second terminal and Third terminal open your default terminal, each with its own window class. Custom… takes any command. |
| Window class | The app-id of the window the pad holds. The app must open its window with this class. Each pad needs its own: pick the class named for the terminal choice the pad uses, or type the app-id your custom app sets. |
| Width, Height | The pad's size, in percent of the screen's free area. |
| Position | Where the pad sits: the centre, an edge or a corner. |
| Margin | The space between the pad and the screen edge it sits at, in percent of the shorter side of the screen's free area. |
| Comes in from | The side the pad slides in from and back out to. |
| Motion | Slide, fade or none. |
| Screen | The screen the pad opens on: the focused one, or one by name. |
| Start at login | Starts the app when VGS starts, hidden. |

A new pad has no key. Set one in the Keys section of the same page.

A new pad takes the Terminal choice and its window class. For a second terminal pad, pick Second terminal and its class, `org.vgs.pad.2`. While two pads share a window class, the later one opens nothing, and its key shows a message that says so.

## Known limits

- Hyprland has one animation for every hidden workspace it shows. A pad sets it each time it shows or hides, so a hidden workspace of your own moves the way the last pad did, until Hyprland reloads its settings.
- A pad is sized inside its screen's free area. A `dwindle:special_scale_factor` below 1 in your Hyprland settings makes every pad smaller than its size.
- While a pad is shown, the desktop behind your windows on its screen shows the theme's background colour when the Themes plugin draws no wallpaper there.
- An app that opens its window with another class than the pad names is never shown. After 15 seconds a message says so.

## Developer interface

| Path | How |
|---|---|
| Shortcut | `vgs.scratchpads:pad-<name>` for each pad, with no default key. |
| Setting | `pads`, a list of `{ name, command, class, width, height, position, margin, entry, motion, screen, preload }` in the plugin's `plugins[]` row. |
| Hyprland | `hyprland.pads` names `pads`: the core writes each pad's window rule and the toggle the service sends ([docs/architecture/hyprland.md](../../../docs/architecture/hyprland.md)). |
| Status | `shown`, which pad each screen shows, and `screens`, the screen choices. |

The service registers each pad's shortcut and follows each pad's window from Hyprland's `openwindow` and `closewindow` events. A press sends `shell.compositor.togglePad`. When the layer answers that the pad's workspace holds no window, the service moves a known window that left it back in, or runs the app with `sh -c` and sends the toggle once Hyprland reports a window of the pad's class, if you still want the pad then. More presses during the start change that wish. When the layer answers that it holds no such pad, as for a pad whose class another pad uses, the service starts nothing and shows a message. The `background` instance on each screen is shown only while a pad is shown there; it draws nothing and hides the pad on a press. The layer moves a window no pad holds any more to the focused workspace each time it loads. The facts this rests on are in [runtime-hyprland-pads.md](../../../docs/architecture/runtime-hyprland-pads.md).

## Validation

`scripts/smoke/rows/scratchpads.sh` makes pads from the Settings window in the nested sandbox and types the key on the nested seat. It reads a second pad on the first one's class reported, with its key kept and a message on a press. It reads that the pad is never shown empty while its slow app starts, that it shows at its shares and anchor at three output modes, at scale 2 and after a mode change, on the screen it names whatever monitor the pointer is on, and that bursts of presses toggle it once each. It reads a window moved out coming back, a change of size, position, entry or motion taking effect on the next press, a press beside the pad or a focus move hiding it, an app that opens no window ending in one message, and a restarted shell starting no second app. Turning the plugin off or removing the pad brings its window to the focused workspace. Its controls read an empty pad, a background that takes no press, a layer with no gaps, and a layer with no focus hook and no refit.
