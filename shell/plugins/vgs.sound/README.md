# Sound

Sound changes the volume, the output and input device, and the volume of each app that plays. It adds a bar icon with a flyout, a Sound section in the System window, the volume keys and an on-screen display.

![The System window on its Sound section: the output, the input with its level meter, and an app that plays](../../../docs/images/plugins/vgs.sound-pane.webp)

Screenshot made with `scripts/readme-shots.sh` in the nested sandbox, with the default theme at scale 2, over the sandbox's own PipeWire and its null devices.

## Features

- A bar icon that shows the output level. A click opens the flyout, the mouse wheel changes the volume and a middle click mutes the output. The tooltip names the output and its level.
- A flyout with the output device and its volume, the input device and its volume, and one volume for each app that plays. Sound settings opens the System window on the Sound section.
- A Sound section in the System window with the same controls and a level meter for the input.
- Volume keys that show an on-screen display on the screen you use.

## Keys

| Key | Action |
|---|---|
| `XF86AudioRaiseVolume` | Raise the volume by the volume step. |
| `XF86AudioLowerVolume` | Lower the volume by the volume step. |
| `XF86AudioMute` | Mute or unmute the output. |
| `XF86AudioMicMute` | Mute or unmute the microphone. |

Settings' Keys rows change each key. When one of your own Hyprland binds uses the same key, the row says so and offers Use my binding. Use my binding turns off the Sound key, so your bind keeps the key.

## Settings

| Setting | Values | What it does |
|---|---|---|
| Volume step | 2%, 5% or 10% | How much the volume keys and the mouse wheel change the volume. The default is 5%. |

## How it works

- Sound reads PipeWire inside the shell. It starts no process to read or change a volume.
- The volume changes the device you hear. When the default output is a filter chain or EasyEffects, the volume goes to the device the filter plays to. The loudness changes and the sound of the filter does not.
- A volume key or the mouse wheel never raises a level past 100%. A level another program set above 100% stays where it is on a step up and steps down from there.
- When you choose an output, it becomes the default. With `pactl` installed, the apps that play now move to it. Sound moves only apps, never EasyEffects or the output of a filter chain.
- Without `pactl`, new apps use the new output and the apps that play now stay where they are. The Playing apps row on the Settings page and in the System window says so and offers to install it.
- Sound reads its device lists a short time after PipeWire changes, so a device that goes away does not stop the shell.
- The input level meter listens to PipeWire only while the Sound section is open.
- While PipeWire is not running, the bar icon shows a crossed speaker and the controls say that sound is not available. Sound connects again when PipeWire starts.

## Requirements

| Command | Package | Use |
|---|---|---|
| `pactl` | `libpulse` on Arch, `pulseaudio-utils` on Debian and Fedora | Optional. Moves the apps that play now to the output you choose. |

## Validation

- `scripts/test-sound-logic.js` holds the decisions: the level icon, the volume step and its limits, the mouse wheel, which streams a new output takes and the device a volume change reaches behind a filter.
- `scripts/smoke/rows/sound.sh` runs Sound in the nested sandbox over the sandbox's own PipeWire, which has null devices only. An app that starts while the section is open gets its row, and the bar icon follows a volume set in the System window. A new output becomes the default and takes an app that plays. A volume change behind the filter chain reaches the device. A key steps the volume by the setting's step, keeps a level above 100%, and shows the display on the focused output alone. Stopped PipeWire shows Sound as not available, and Sound connects again when PipeWire starts, whether it stopped while the shell ran or before the shell started. The keyboard alone reaches every control of the Sound section, and Use my binding gives a key back to a user bind.
