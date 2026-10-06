# Capture

Capture takes PNG screenshots. It can save them, copy them, or do both. It also records the screen and copies text from a selected area in the languages you choose.

![Capture widget](../../../docs/images/plugins/vgs.capture-widget.webp)

![Capture panel](../../../docs/images/plugins/vgs.capture-panel.webp)

Images come from `scripts/readme-shots.sh` in the nested sandbox.

## Features

- Screenshot of the focused output, of an area, of a window, of a chosen display, or one image of all displays.
- Area selection over a still screen. A click selects the window or display under the pointer. Escape or the same key cancels.
- Screenshot delay with a countdown in the bar. The same key or a click on the countdown cancels.
- Choice of save and copy, copy only, or save only. The pointer is optional.
- Screen recording of an area, a window, a chosen display, the focused display, or what the desktop's screen picker shares.
- Recording quality, frame rate, codec, constant frame rate and pointer choices.
- Desktop audio, microphone audio, both or neither, plus extra audio sources, each on its own track.
- An optional camera picture in the corner of a recording.
- Finished recordings lose their first tenth of a second and get even loudness.
- Text recognition from a selected area in one or more languages.
- A notification for each finished capture. Open and Edit start your own image viewer, image editor or video player.
- A panel from the bar: choose Screenshot, Record or Text, choose what to capture, then press one button. While a recording runs, the button stops it.
- A few options under the button for each choice: what happens after a screenshot, the delay, the pointer, the recording audio, quality and camera, and the text language. The Settings page holds every other option.
- A recording indicator in the bar. A click on the indicator, or the recording shortcut again, stops and saves.
- Shortcuts: Print for a screenshot, `SUPER+SHIFT+S` for an area, `SUPER+SHIFT+R` for a recording, `SUPER+CTRL+PRINT` for text and `SUPER+CTRL+SHIFT+S` for the panel. A recording of the focused display has no key until you set one. The Keys row on the plugin's Settings page changes them.

## Settings

| Setting | What it changes |
| --- | --- |
| Screenshot result | Save and copy, copy only, or save only. |
| Screenshot delay | Seconds before the screenshot, with a countdown in the bar. |
| Screenshot folder | Empty uses Screenshots in your Pictures folder. A custom folder is an absolute path or starts with `~/`. |
| Recording folder | Empty uses Screencasts in your Videos folder. |
| Recording audio | None, desktop, microphone or both. |
| Text languages | Codes joined by +, such as eng+deu. English is installed with Capture. Install languages adds the data for the other chosen languages. |
| Image viewer, Image editor, Video player | The command each notification button starts, with `%f` as the file. imv, Satty and mpv are the defaults. |

Every saved recording puts its file link on the clipboard, which replaces what the clipboard held. Recording needs gpu-screen-recorder, which the Arch and NixOS packages provide. A missing tool opens the install notice for the action that needs it.

[developer.md](developer.md) states each action and its IPC name.
