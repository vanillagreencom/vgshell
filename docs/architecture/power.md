# Every stage of the idle path has one owner and counts from the last input

Read before touching the idle path, a stage of dim, screensaver, display off, lock or sleep, a wake from sleep, an inhibitor, an energy setting, a wake source, the power button or the lid.

## The approach

The idle path is a set of stages. Each stage has one owner, and each owner holds its own watch on the core's idle source, `shell/Core/IdleRegistry.qml`, lent through capability `idle` ([D062](../decisions/D062-native-lock-and-polkit-plugins.md)). A watch counts from the later of the last input the seat saw and the watch's own creation, since Hyprland starts a notification's timer when the shell creates it. No owner reads another owner's setting, so any order of values has a defined result. `vgs.power` is the one energy plugin. The choice is [D109](../decisions/D109-idle-path-one-owner-per-stage.md).

Today the code holds the idle source, the dim, the screensaver, the lock, the lock before sleep, display off, disk sleep, wake sources and Wake on LAN. Every other row below is designed: the named child item adds its code and its pin, and until then no code holds it.

| Stage | Owner | What it does | State |
|---|---|---|---|
| Idle source | core `IdleRegistry` | one `IdleMonitor` per watch, inhibitors obeyed | holds |
| Stage record | core | the stages in order with each one's time, read-only | VGS-1902 |
| Dim | `vgs.displays` | lowers each panel's brightness, puts it back on input | holds |
| Screensaver | `vgs.screensaver` | shows the Cover, a layer surface per screen, never while locked | holds; stops while the panels are off: VGS-1904 |
| Lock | `vgs.lock` | locks once; input does not unlock | holds |
| Lock before sleep | `vgs.lock` | holds a logind delay inhibitor and locks on `PrepareForSleep` | holds |
| Display off | `vgs.power` | turns every panel off after idle, and sooner while locked | holds |
| Sleep after idle | `vgs.power` | asks logind to suspend, hibernate or suspend then hibernate | VGS-1907 |
| Resume | `vgs.power` | turns the panels on and restarts its own watches after a wake from sleep | VGS-1906 |
| Session Sleep and Hibernate actions | `vgs.power` | launcher rows, offered only while logind answers yes | VGS-1908 |
| Power button and lid | logind, set by `vgs.power` through system steps | the action the key or the lid takes | VGS-1909 |
| Wake sources | `vgs.power` through a system step and BlueZ | keyboards, pointers, the power button and USB connection changes can wake the machine | holds |
| Wake on LAN | `vgs.power` through NetworkManager | on or off per wired connection | holds |
| Disk sleep | `vgs.power` through a system step | spins down idle rotational disks | holds |
| Power profiles, battery alerts | `vgs.power` | as today | holds |

The greeter's Suspend button is a separate surface before login, outside the user session and outside this path. `vgs.greeter` owns it.

Each owner's manifest schema holds its settings, defaults and ranges. Designed in VGS-1902: a plugin declares the stage it owns and the setting that holds its time in its manifest, and the core lends the stages as one read-only record, `shell.idle.stages`, in the fixed order dim, screensaver, lock, display off, sleep. Each entry names the owner, the setting and the time, Never included, and the earlier stages it fires before. The core reads the times from the effective configuration, so no plugin reads another plugin.

The `vgs.power` pane in System Settings > Hardware holds its own fields and shows the whole idle timeline from `shell.idle.stages`; `scripts/smoke/rows/power.sh` pins it. Each row shows its stage's time, links to the owner's field with a page reference, and says so on the row when the stage fires before an earlier one, such as a lock before the screensaver or display off before the dim. This applies the overseer's ruling on ask 1792375461-2156217-9760: the pane links to each owner's field and shows every time in one place.

A plugin cannot call `Hyprland.dispatch`; every runtime request goes through the core `Compositor` queue, built and judged by `shell/Core/Dispatch.js`, and a plugin reaches it only through the dispatchers capability `compositor` lends ([hyprland.md](hyprland.md) § Dispatch). Designed in VGS-1903:

- Display power is a new dispatcher, `displayPower(state)`, `off` or `on`, with no output named, so both connectors of a tiled Pro Display XDR change together. For `on`, the core reads the outputs first and sends nothing while every output reads on, since a DPMS on that changes nothing makes a panel modeset again.
- The core's Hyprland layer sets `misc.key_press_enables_dpms` and `misc.mouse_move_enables_dpms`, so a key press or a pointer move turns every panel on with no shell work, while the shell is down too.
- The core lends a read-only fact, `shell.session.displaysOff` ([D056](../decisions/D056-read-only-session-state.md)): true from a `displayPower("off")` the outputs confirm until the next input or `displayPower("on")`. One core input observer lives from the queued off through confirmation until the fact clears; input after the observer arms and before confirmation invalidates the pending request.

The Apple panels' HID brightness has no power control: 0 % is the lowest backlight, not off. Display off is therefore DPMS.

A wake from sleep has one owner, `vgs.power`, designed in VGS-1906. On logind's `PrepareForSleep(false)` it asks `displayPower("on")` and creates its own watches again, so each counts from the wake. The panels light at a wake whether or not the waking key press, pointer move or power button reaches Hyprland as input. While the session stays locked with no input, the locked display-off watch turns them off again.

Every root change of this path is a row of the closed table in `bin/vgshell-system` ([commands-are-data.md](commands-are-data.md) § System steps). Designed in VGS-1909: a step may take one value from a closed set its table row names. The power button and the lid act through logind, which keeps working while the shell is down.

### Window events and the idle count

Hyprland restarts every inhibitor-obeying idle notification each time a window maps, unmaps or takes keyboard focus. It recomputes the inhibitor state at each of these events and resets the notifications without comparing the result with the previous state. `IdleMonitor` with `respectInhibitors: true` asks for exactly those notifications, so a window that opens, closes or takes focus counts as input for every VGS stage and ends a dim or a screensaver that has started. Layer surfaces do not trigger it, so the Cover and the lock surface do not restart a watch. hypridle uses the same notification by default and behaves the same.

VGS does no work on this behaviour. It keeps `respectInhibitors: true`, because a watch that ignores inhibitors would let a playing video dim, blank and lock the screen. It ships no patched Hyprland and builds no inhibitor reader of its own. A nested test compositor on the live desktop was one such window source; VGS-1898 removes it, so a test run puts no window on the live desktop.

## Why

Omarchy runs one idle monitor and timers for later stages, because its screensaver is a terminal window and mapping it restarts the count. The VGS Cover and lock are layer surfaces, so separate watches stay correct and need no cycle state to keep.

A plugin cannot read another plugin ([overview.md](overview.md)), so stage order cannot be a check across owners. Counting each stage on its own gives every order a defined result: a screensaver due after the lock never starts, because it refuses while locked; panels off before the lock stay off until input; a sleep before the lock still locks first through the delay inhibitor while Lock before sleep is on. The core already holds every plugin's effective settings, so the one place that can show the order without one plugin reading another is a core record built from what each plugin declares.

`vgs.power` already owns power profiles and battery alerts. Energy is one concern, so it grows and keeps its id; a new `vgs.energy` would need `formerIds` ([D108](../decisions/D108-renamed-plugin-declares-former-ids.md)) and gain nothing.

DPMS is one compositor state for the whole session, with no per-panel backend in VGS. `vgs.displays` keeps brightness and the dim. Once the wake options are written, Hyprland wakes the panels on input before any shell code runs, so the shell sends DPMS on only at a wake from sleep, where the waking event may never reach Hyprland as input. A plugin cannot read the lock's password check, so the locked delay is longer than a check takes instead of a guard on it.

An idle notification's timer runs on the compositor's monotonic clock, which stops during suspend, so a watch that had partly run can fire soon after a wake unless input reset it. That is the case Omarchy's re-arm of its frozen blank timer covers. `vgs.power` covers it by creating its watches again at the wake. For the other stages an early fire after a wake does no harm: the lock already holds, the screensaver refuses while locked, and the dim ends on the next input.

A Cover left running behind dark panels would keep a `ttfx` process and a frame timer per screen busy for as long as the user is away. The screensaver cannot read `vgs.power`, so the core, which sends the DPMS request, lends the fact that the panels are off, and the screensaver stops on it.

logind is the one judge of what the system can do: it answers `CanSuspend`, `CanHibernate` and `CanSuspendThenHibernate`, and it applies sleep inhibitors and the lock's delay to every request that goes through it. Omarchy's own hibernate check reads an Omarchy-written file and repeats part of what logind checks.

The power button and the lid must act while the shell is down: a laptop closed into a bag must still sleep. A shell bind with logind told to ignore the key would fail there.

## Rules

### Idle source and stages

- Do create every idle watch through `shell.idle.watch`, and release it through the disposer it returns. A plugin cannot import `Quickshell.Wayland`, which `scripts/check-plugin-boundary.py` refuses; `scripts/smoke/rows/capability-release.sh` pins the release.
- Do keep `respectInhibitors: true` on every idle stage watch, as § Window events and the idle count sets out. A watch that clears a fact on input and starts no stage ignores inhibitors. Review holds it.
- Never read another stage owner's setting or status; read another stage's time only from `shell.idle.stages`. Gap: `vgs.screensaver` reads `vgs.lock`'s `idleLockSeconds` through capability `manager` for its `lockOrder` reading. Designed: VGS-1902 adds the record with its rows in `scripts/test-plugin-logic.js`, and VGS-1904 moves `lockOrder` onto it.
- Do judge stage order in one place, the core record; the pane and the screensaver show its verdict and never compute their own. Designed: VGS-1902.
- Do keep the Cover and the lock surface on layer surfaces, so showing them does not restart another watch. Gap: no row checks it; VGS-1904 adds the check that the lock still engages on time while the Cover runs.
- Do stop the Cover and its effect while `shell.session.displaysOff` is true, and start none while it is. Designed: VGS-1904 pins it in `scripts/smoke/rows/screensaver.sh`.
- Never create an idle inhibitor or an idle pause in a plugin. A stay-awake pause, if one is added, is core-owned and lent through capability `idle` with a disposer. Review holds it.
- Do honour Wayland idle inhibitors, through Hyprland, and Hyprland's own `idle_inhibit` window rules, which the user writes. VGS ships no such rule. VGS does not honour `org.freedesktop.ScreenSaver` inhibits, because Quickshell 0.3.1 cannot own a D-Bus object ([D085](../decisions/D085-bluetooth-agent-core-lent-over-bluetoothctl.md)), and does not read logind idle inhibitors. Review holds it.

### Display off and resume

- Do change panel power only through `shell.compositor.displayPower`, one request with no output named. Designed: VGS-1903 adds it with its rows in `scripts/test-dispatch.js` and its readback in `scripts/smoke/rows/compositor-dispatchers.sh`.
- Never turn off one connector of a physical monitor. Designed: the dispatcher takes no output argument, pinned by `scripts/test-dispatch.js` in VGS-1903.
- Do send DPMS on only from `vgs.power` at a wake from sleep; input wakes the panels through Hyprland's options. Designed: VGS-1903 writes the options, pinned by `scripts/test-hyprland-layer.js`, and VGS-1906 pins the wake in `scripts/smoke/rows/power.sh`.
- Do turn the panels off while locked a fixed short time after the lock or the last input, whichever is later, and never while the display-off setting is Never. `vgs.power/Service.qml` owns both watches; `scripts/smoke/rows/power.sh` pins their timers and release.

### Sleep

- Do default sleep after idle to Never. Designed: VGS-1907; review holds the default.
- Do suspend and hibernate only through logind, so the lock's delay inhibitor and every block inhibitor apply. Designed: VGS-1907 pins the request with a stand-in in `scripts/smoke/rows/power.sh`.
- Do offer Hibernate and Suspend then hibernate, as a setting value, a launcher row or a key action, only while logind answers yes. Designed: VGS-1907 and VGS-1908.
- Never run a check that suspends or hibernates a real machine. Sandbox rows use a stand-in for logind, as `scripts/smoke/rows/lock.sh` does today. Review holds it.

### Keys, wake and storage

- Do set the power button and the lid as logind drop-ins written by a system step, never as a shell bind over a key logind ignores. Designed: VGS-1909 adds a step that takes one value from the closed set its row in `bin/vgshell-system` names, the one owner of that set, pinned by `scripts/test-vgshell-system.sh`.
- Never restart `systemd-logind` to apply a drop-in. Designed: VGS-1909 states the reload route it measured.
- Do enable USB wake on devices with a HID boot keyboard or mouse interface, every USB hub including root hubs, and Bluetooth controllers. Disable it on other wake-capable USB devices. `config/system/udev/90-vgs-wake.rules` writes only `power/wakeup`, with no helper or topology reconciliation. The `wake-sources` system step probes the live attributes, reloads the rule and triggers USB change events on apply and undo. `scripts/test-vgshell-system.sh` pins the probe and ownership refusal; `scripts/smoke/rows/system-steps.sh` reads the step in the fake system tree.
- Do accept that connecting a device to any USB port during sleep can wake the machine. Linux v6.17 [hub.c, lines 3992–4001](https://github.com/torvalds/linux/blob/v6.17/drivers/usb/core/hub.c#L3992-L4001) arms connect and disconnect wake for every superspeed hub port; [xhci-hub.c, lines 1731 and 1795–1807](https://github.com/torvalds/linux/blob/v6.17/drivers/usb/host/xhci-hub.c#L1795-L1807) applies the root hub's wake permission to port connection events. A device's own remote wake permission is separate: [driver.c, lines 1548–1572](https://github.com/torvalds/linux/blob/v6.17/drivers/usb/core/driver.c#L1548-L1572) reads `device_may_wakeup`, and [hub.c, lines 3509–3517](https://github.com/torvalds/linux/blob/v6.17/drivers/usb/core/hub.c#L3509-L3517) enables device remote wake accordingly. OTG wake signals can bypass that permission, as the same code notes. Hardware acceptance remains the owner's live check after the hold ends.
- Do allow Bluetooth wake only on paired keyboards and pointers, through BlueZ's per-device `WakeAllowed`, written by `vgs.power` once the wake step reads ready. `scripts/smoke/rows/power.sh` pins the writes over stand-in devices on the private bus.
- Do set Wake on LAN on the NetworkManager connection, which reapplies it at each activation; never through `ethtool`. On is `magic` and off is `none`, which NetworkManager applies as Wake on LAN off; `ignore` makes no change and leaves the card armed. Write no connection until the user sets the switch, read each wired connection first and write only one that holds another value, and count only wired devices NetworkManager manages. Persist the first pass's chosen marker through `configure`, so either value reaches connections added later, including after a restart, while the untouched default writes nothing. The value stays on the connections when Power is disabled; the user turns the switch off first. A pass that fails shows its problem under the switch in System Settings → Power and Power's Settings tab, through the schema's `problem` key. `PowerLogic.wakeObserved` holds the rule, `scripts/test-power-logic.js` pins it, and `scripts/smoke/rows/power.sh` pins the writes with a stand-in `nmcli`.
- Do offer disk sleep only while a rotational disk exists; the step's probe reads `absent` without one. `scripts/test-vgshell-system.sh` pins the probe and `scripts/smoke/rows/power.sh` pins the offer.

## The canonical example

`watchIdle()` in `shell/plugins/vgs.lock/Service.qml`: it disposes the previous watch, returns while the setting is off, and watches with the setting's value. Copy it for a new stage.

## Revisit when

- Hyprland compares the inhibitor state before it resets idle notifications, or the owner asks VGS to act on the window-event restart.
- Quickshell can own a D-Bus object, so VGS can honour `org.freedesktop.ScreenSaver` inhibits.
- A stage must draw a window, which would restart every watch, or must know another stage's state beyond the stage record.
- A panel stays dark, or goes dark again over an unlocked session, after a wake from sleep; or an Apple panel stays lit under DPMS off.
- A device connected or disconnected during sleep wakes the machine often enough that the owner asks to stop it.
- The owner asks for a stay-awake toggle.
- A measured time from a sleep request to a secure lock nears the delay budget `vgs.lock` reads from logind.
- VGS targets a laptop's keyboard backlight, a display on a connector logind does not count for the lid, or a game that a gamepad keeps busy while the seat reads idle.

## Not governed

What each stage draws and its own tests, which are its plugin's README and rows. The lock's PAM stack and unlock path, which are [D062](../decisions/D062-native-lock-and-polkit-plugins.md) and `vgs.lock`. The greeter's buttons, which are `vgs.greeter`. Brightness backends and the Apple panels' HID protocol, which are `shell/plugins/vgs.displays/helper/brightness.py`. The system step mechanics, which are [commands-are-data.md](commands-are-data.md). The dispatch queue and the Hyprland layer, which are [hyprland.md](hyprland.md). The nested sandbox, which is [validation.md](validation.md).
