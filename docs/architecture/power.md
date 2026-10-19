# Every stage of the idle path has one owner and counts from the last input

Read before touching the idle path, a stage of dim, screensaver, display off, lock or sleep, an inhibitor, an energy setting, a wake source, the power button or the lid.

## The approach

The idle path is a set of stages. Each stage has one owner, and each owner holds its own watch on the core's idle source, `shell/Core/IdleRegistry.qml`, lent through capability `idle` ([D062](../decisions/D062-native-lock-and-polkit-plugins.md)). Every watch counts from the last input the seat saw, not from the stage before it. No owner reads another owner's setting, so any order of values has a defined result. `vgs.power` is the one energy plugin. The choice is [D109](../decisions/D109-idle-path-one-owner-per-stage.md).

| Stage | Owner | What it does | State |
|---|---|---|---|
| Idle source | core `IdleRegistry` | one `IdleMonitor` per watch, inhibitors obeyed | holds |
| Dim | `vgs.displays` | lowers each panel's brightness, puts it back on input | holds |
| Screensaver | `vgs.screensaver` | shows the Cover, a layer surface per screen, never while locked | holds |
| Lock | `vgs.lock` | locks once; input does not unlock | holds |
| Lock before sleep | `vgs.lock` | holds a logind delay inhibitor and locks on `PrepareForSleep` | holds |
| Display off | `vgs.power` | turns every panel off after idle, and sooner while locked | [child: display-off] |
| Sleep after idle | `vgs.power` | asks logind to suspend, hibernate or suspend then hibernate | [child: sleep] |
| Sleep and Hibernate actions | `vgs.power` launcher rows; `vgs.greeter` its own button | offered only while logind answers yes | [child: sleep-actions] |
| Power button and lid | logind, set by `vgs.power` through system steps | the action the key or the lid takes | [child: step-values], [child: keys] |
| Wake sources | `vgs.power` through a system step and BlueZ | only keyboards, pointers and the power button wake the machine | [child: wake-step], [child: wake] |
| Wake on LAN | `vgs.power` through NetworkManager | on or off per wired connection | [child: wol] |
| Disk sleep | `vgs.power` through a system step | spins down idle rotational disks | [child: disk-step], [child: disk] |
| Power profiles, battery alerts | `vgs.power` | as today | holds |

A row marked with a child item is the designed state; that item adds the code and its pin. Each owner's manifest schema holds its settings, defaults and ranges. The `vgs.power` pane in Settings > Hardware (VGS-1899) holds its own fields and links to the dim, screensaver and lock fields of their owners with page references.

Display off is one global DPMS request. A plugin may not dispatch, so the request is a core dispatcher, `displaysOff`, built in `shell/Core/Dispatch.js` and lent through capability `compositor` ([hyprland.md](hyprland.md) § Dispatch). It names no output, so both connectors of a tiled Pro Display XDR go off together. The Apple panels' HID brightness has no power control: 0 % is the lowest backlight, not off. Hyprland itself wakes the panels: the core's Hyprland layer sets `misc.key_press_enables_dpms` and `misc.mouse_move_enables_dpms`, so a key press or a pointer move on the lock screen or the desktop turns every panel on with no shell work. The shell never asks for DPMS on.

Every root change of this path is a row of the closed table in `bin/vgshell-system` ([commands-are-data.md](commands-are-data.md) § System steps). The power button and the lid act through logind, which keeps working while the shell is down.

### Window events and the idle count

Hyprland restarts every inhibitor-obeying idle notification each time a window maps, unmaps or takes keyboard focus. It recomputes the inhibitor state at each of these events and resets the notifications without comparing the result with the previous state. `IdleMonitor` with `respectInhibitors: true` asks for exactly those notifications, so a window that opens, closes or takes focus counts as input for every VGS stage and ends a dim or a screensaver that has started. Layer surfaces do not trigger it, so the Cover and the lock surface do not restart a watch. hypridle uses the same notification by default and behaves the same.

VGS does no work on this behaviour. It keeps `respectInhibitors: true`, because a watch that ignores inhibitors would let a playing video dim, blank and lock the screen. It ships no patched Hyprland and builds no inhibitor reader of its own. A nested test compositor on the live desktop was one such window source; VGS-1898 removes it, so a test run puts no window on the live desktop.

## Why

Omarchy runs one idle monitor and timers for later stages, because its screensaver is a terminal window and mapping it restarts the count. The VGS Cover and lock are layer surfaces, so separate watches stay correct and need no cycle state to keep.

A plugin cannot read another plugin ([overview.md](overview.md)), so stage order cannot be a check across owners. Counting each stage from the last input gives every order a defined result: a screensaver due after the lock never starts, because it refuses while locked; panels off before the lock stay off until input; a sleep before the lock still locks first through the delay inhibitor while Lock before sleep is on.

`vgs.power` already owns power profiles and battery alerts. Energy is one concern, so it grows and keeps its id; a new `vgs.energy` would need `formerIds` ([D108](../decisions/D108-renamed-plugin-declares-former-ids.md)) and gain nothing.

DPMS is one compositor state for the whole session, with no per-panel backend in VGS. `vgs.displays` keeps brightness and the dim. Hyprland wakes the panels before any shell code runs, and also while the shell is down, so the shell sends no DPMS on. This drops two of Omarchy's guards: its skip of a redundant DPMS on after resume, and its re-arm of a blank timer that a suspend froze, since VGS counts with idle watches and not timers. A plugin cannot read the lock's password check, so the locked delay is longer than a check takes instead of a guard on it.

logind is the one judge of what the system can do: it answers `CanSuspend`, `CanHibernate` and `CanSuspendThenHibernate`, and it applies sleep inhibitors and the lock's delay to every request that goes through it. Omarchy's own hibernate check reads an Omarchy-written file and repeats part of what logind checks.

The power button and the lid must act while the shell is down: a laptop closed into a bag must still sleep. A shell bind with logind told to ignore the key would fail there.

## Rules

### Idle source and stages

- Do create every idle watch through `shell.idle.watch`, and release it through the disposer it returns. A plugin cannot import `Quickshell.Wayland`, which `scripts/check-plugin-boundary.py` refuses; `scripts/smoke/rows/capability-release.sh` pins the release.
- Do keep `respectInhibitors: true` on every watch, as § Window events and the idle count sets out. Review holds it.
- Never read another stage owner's setting or status to order the stages. Gap: `vgs.screensaver` reads `vgs.lock`'s `idleLockSeconds` through capability `manager` for its `lockOrder` reading; [child: idle-pin] removes it, and review holds the rule after.
- Do keep the Cover and the lock surface on layer surfaces, so showing them does not restart another watch. Gap: no row checks it; [child: idle-pin] adds the check that the lock still engages on time while the Cover runs.
- Never create an idle inhibitor or an idle pause in a plugin. A stay-awake pause, if one is added, is core-owned and lent through capability `idle` with a disposer. Review holds it.
- Do honour Wayland idle inhibitors, through Hyprland, and Hyprland's own `idle_inhibit` window rules, which the user writes. VGS ships no such rule. VGS does not honour `org.freedesktop.ScreenSaver` inhibits, because Quickshell 0.3.1 cannot own a D-Bus object ([D085](../decisions/D085-bluetooth-agent-core-lent-over-bluetoothctl.md)), and does not read logind idle inhibitors. Review holds it.

### Display off

- Do turn panels off only through `shell.compositor.displaysOff()`, one request with no output named. Designed: [child: dpms-core] adds it with its rows in `scripts/test-dispatch.js` and its readback in `scripts/smoke/rows/compositor-dispatchers.sh`.
- Never send DPMS on from the shell, and never turn off one connector of a physical monitor. Designed: [child: dpms-core] writes the two Hyprland wake options in the layer, pinned by `scripts/test-hyprland-layer.js`.
- Do turn the panels off while locked after a fixed short time without input, and never while the display-off setting is Never. Designed: [child: display-off] pins it in `scripts/smoke/rows/power.sh`.

### Sleep

- Do default sleep after idle to Never. Designed: [child: sleep]; review holds the default.
- Do suspend and hibernate only through logind, so the lock's delay inhibitor and every block inhibitor apply. Designed: [child: sleep] pins the request with a stand-in `systemctl` in `scripts/smoke/rows/power.sh`.
- Do offer Hibernate and Suspend then hibernate, as a setting value, a launcher row or a key action, only while logind answers yes. Designed: [child: sleep] and [child: sleep-actions].
- Never run a check that suspends or hibernates a real machine. Sandbox rows use a stand-in for logind, as `scripts/smoke/rows/lock.sh` does today. Review holds it.

### Keys, wake and storage

- Do set the power button and the lid as logind drop-ins written by a system step, never as a shell bind over a key logind ignores. Designed: [child: step-values] adds a step that takes one value from a closed set, pinned by `scripts/test-vgshell-system.sh`.
- Never restart `systemd-logind` to apply a drop-in. Designed: [child: step-values] states the reload route it measured.
- Do allow wake only from USB keyboards and pointers, the hubs and Bluetooth controllers above them, and the power button. Designed: [child: wake-step] ships the udev rule and its step.
- Do allow Bluetooth wake only on paired keyboards and pointers, through BlueZ's per-device `WakeAllowed`, written by `vgs.power` once the wake step reads ready. Designed: [child: wake].
- Do set Wake on LAN on the NetworkManager connection, which reapplies it at each link up. Designed: [child: wol].
- Do offer disk sleep only while a rotational disk exists; the step's probe reads `absent` without one. Designed: [child: disk-step].

## The canonical example

`watchIdle()` in `shell/plugins/vgs.lock/Service.qml`: it disposes the previous watch, returns while the setting is off, and watches with the setting's value. Copy it for a new stage.

## Revisit when

- Hyprland compares the inhibitor state before it resets idle notifications, or the owner asks VGS to act on the window-event restart.
- Quickshell can own a D-Bus object, so VGS can honour `org.freedesktop.ScreenSaver` inhibits.
- A stage must draw a window, which would restart every watch, or must know another stage's state.
- The owner asks for a stay-awake toggle.
- A measured time from a sleep request to a secure lock nears the delay budget `vgs.lock` reads from logind.
- VGS targets a laptop's keyboard backlight, a display on a connector logind does not count for the lid, or a game that a gamepad keeps busy while the seat reads idle.

## Not governed

What each stage draws and its own tests, which are its plugin's README and rows. The lock's PAM stack and unlock path, which are [D062](../decisions/D062-native-lock-and-polkit-plugins.md) and `vgs.lock`. Brightness backends and the Apple panels' HID protocol, which are `shell/plugins/vgs.displays/helper/brightness.py`. The system step mechanics, which are [commands-are-data.md](commands-are-data.md). The dispatch queue and the Hyprland layer, which are [hyprland.md](hyprland.md). The nested sandbox, which is [validation.md](validation.md).
