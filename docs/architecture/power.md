# Every idle stage has one owner

Read before touching idle stages, inhibitors, sleep, wake, energy settings, the power key or the lid.

## The approach

Each stage owns its watch through core `IdleRegistry.qml`. Watches count from the later of seat input and watch creation. Each owner uses its own settings; the core's read-only stage record supplies cross-stage times and order ([D062](../decisions/D062-native-lock-and-polkit-plugins.md), [D109](../decisions/D109-idle-path-one-owner-per-stage.md)). `vgs.power` owns energy features, including display power, sleep, wake, profiles and battery alerts. Display brightness and dim remain with `vgs.displays`.

## Why

Independent stage watches give every ordering a defined result without plugin dependencies. Layer-surface covers and locks do not themselves restart the idle count. logind owns sleep capability and inhibitors, so every sleep request follows the same safety boundary even when it comes from outside VGS.

## Rules

### Idle source and stages

- Create and release watches through capability `idle`. Keep every stage watch inhibitor-obeying; only an input observer that starts no stage ignores inhibitors. `scripts/check-plugin-boundary.py` refuses direct Wayland imports, and `scripts/smoke/rows/capability-release.sh` checks disposal.
- Accept Hyprland's inhibitor-obeying notification resets on window mapping, unmapping and keyboard focus. Keep no separate inhibitor reader and ship no Hyprland patch to change this behavior. Review holds this boundary.
- Read another stage's time only through `shell.idle.stages`, never its owner's settings or status. Judge order once in the core. The Power pane links to each owner's field and shows every time, including an earlier stage overtaken by a later one. `PluginLogic.idleStages` owns the record; `scripts/smoke/rows/power.sh` checks its use.
- Take stage-owned watches through `shell.idle.watchStage`. Only that stage's owner can take its watch. Carry its core-issued ticket into idle lock and screensaver requests; input, disposal and owner or time changes revoke it. `scripts/test-plugin-logic.js` and `scripts/test-session-lock.sh` check authorization.
- Keep Cover and lock on layer surfaces. During idle lock, take the lock first and move the same running Cover into it, without building a lock screen underneath. Manual, sleep and restore locks end Cover. `scripts/smoke/rows/secure-cover.sh` checks presentation ownership.
- When lock and screensaver times are equal and positive, start from the lock's idle event regardless of notification order. Recreate no watch and move no deadline. Editing the screensaver time must not recreate the lock watch. A later notification starts nothing over an established lock. `scripts/smoke/rows/secure-cover.sh` checks the boundary.
- End a held Cover on real input through the core barrier, so that input reaches neither the lock screen nor PAM. Also end it on display off, owner-reported failure, loss of owner or last instance, unlock or superseding lock. Keep the lock. A cover with no built instance starts no presentation. `scripts/smoke/rows/secure-cover.sh` checks these boundaries.
- Stop Cover and its effect while `shell.session.displaysOff` is true and start none. The core cover-presentation owner enforces it; `scripts/smoke/rows/screensaver.sh` checks it.

### Pause ownership

- Create no plugin-owned idle inhibitor or pause. The core owns ScreenSaver inhibits and Stay awake holds. `shell.idle.stayAwake` lends an instance-bound hold with one end time; release, disable, rebuild and shell exit end it. Keep the wall-clock recheck at least once a minute so suspend cannot prolong an expired hold beyond a minute after wake. `scripts/smoke/rows/stay-awake.sh` checks lifetime; `PluginLogic.stayAwakeWait` owns the timer bound.
- Keep `vgs.power`'s Stay awake hold independent of idle and sleep settings. End it at the critical-battery notice. `scripts/smoke/rows/power.sh` checks release and saved settings.
- Honor Wayland inhibitors through Hyprland and user-written `idle_inhibit` rules. VGS ships no such rule. Review holds it.
- Answer `org.freedesktop.ScreenSaver` only through `bin/vgshell-idle-inhibit`, while an enabled plugin has a stage that can fire ([D116](../decisions/D116-screensaver-inhibits-answered-by-a-core-helper.md)). Leave an existing bus owner in place and log that fact once. Pause all watches while any inhibit is live. Shell or helper restart drops inhibits and fails open until applications ask again. VGS answers neither PowerManagement nor portal Inhibit and reads no logind idle inhibitors. `scripts/smoke/rows/idle-inhibit.sh` checks this boundary.

### Display off and resume

- Change panel power only through `shell.compositor.displayPower`, with no output argument. Never power off just one connector of a physical monitor. Use DPMS rather than brightness as power control. `scripts/test-dispatch.js` checks the request grammar.
- Keep redundant-on suppression and off confirmation in the core queue. Arm the input observer before dispatching off; input after arming invalidates the pending request. Publish `shell.session.displaysOff` only after output confirmation and clear it on input or on. `scripts/smoke/rows/compositor-dispatchers.sh` checks effects ([D056](../decisions/D056-read-only-session-state.md)).
- Let Hyprland's key and pointer options wake panels on input, including while the shell is down. Send DPMS on from `vgs.power` only at resume from sleep and recreate its own watches then. A wake need not reach Hyprland as input. `scripts/test-hyprland-layer.js` and `scripts/smoke/rows/power.sh` check these paths.
- While locked, count the short display-off delay from the later of lock and input. Respect inhibitors and the Never setting. `vgs.power/Service.qml` owns the watches; `scripts/smoke/rows/power.sh` checks them.

### Sleep and power actions

- Default idle sleep to Never. Suspend and hibernate only through logind so block and lock-delay inhibitors apply. Offer sleep methods only while logind answers yes. `scripts/test-power-logic.js` checks the method judge; `scripts/smoke/rows/power.sh` checks requests.
- Keep explicit launcher Sleep, the sleep shortcut and idle sleep on `vgs.power`'s noninteractive request owner. Explicit Sleep requests Suspend independently of the saved idle action. `scripts/smoke/rows/launcher.sh` checks the launcher route.
- Run power-menu actions, launcher Log out, Reboot and Shut down, and Updates Reboot through `bin/vgshell-power`'s fixed verbs. Offer only available actions and retain the continuous confirmation hold. `scripts/test-vgshell-power.sh` and `scripts/test-power-logic.js` check routing and admission; the code owns the verb set and hold duration.
- Keep suspend and hibernate on logind's systemctl route. Lock before asking LightDM to switch user; a failed lock permits no switch. `scripts/test-vgshell-power.sh` checks ordering.
- Never test with a real suspend or hibernate request. Nested rows use the shared logind stand-in. Review holds this host-safety boundary.

### Keys, wake and storage

- Keep power-button and lid authority in logind through closed system steps, never a shell bind over an ignored logind key. Restart no `systemd-logind` to apply a drop-in. Review holds this design boundary; the power-button and lid step is not implemented.
- Enable USB wake for HID boot keyboards and mice, hubs including root hubs, and Bluetooth controllers. Disable other wake-capable USB devices. Keep the udev rule limited to `power/wakeup`, without a helper or topology reconciliation. The `wake-sources` system step owns probing, rule reload and change events. `scripts/test-vgshell-system.sh` checks that ownership.
- Accept connection and disconnection wake while hubs are armed. Device remote-wake permission does not control every port event or OTG wake. The implementation sources are the Linux [USB hub](https://github.com/torvalds/linux/blob/v6.17/drivers/usb/core/hub.c), [xHCI hub](https://github.com/torvalds/linux/blob/v6.17/drivers/usb/host/xhci-hub.c) and [USB driver](https://github.com/torvalds/linux/blob/v6.17/drivers/usb/core/driver.c). Hardware acceptance remains the owner's live check.
- Permit Bluetooth wake only for paired keyboards and pointers through per-device BlueZ `WakeAllowed`, after the wake step is ready. `scripts/smoke/rows/power.sh` checks writes on stand-ins.
- Set Wake on LAN through NetworkManager connections, never ethtool. Read each managed wired connection and change only differing values. Preserve explicit user intent across later connections and restart; an untouched default writes nothing. Disabling Power leaves connection values intact, so the user turns the switch off first. `PowerLogic.wakeObserved` owns the decision; `scripts/smoke/rows/power.sh` checks writes and reported failures.
- Offer disk sleep only when the system step finds a rotational disk. `scripts/test-vgshell-system.sh` checks absence; `scripts/smoke/rows/power.sh` checks the offer.

### Temporary lock release

- Grant a release with Lock before sleep on only after the sleep hook confirms logind is not preparing to sleep. Clear readiness before a sleep lock and on hook start or stop; secure-lock acknowledgement grants no readiness. An unread sleep state keeps the inhibitor and grants nothing.
- End a release before acknowledging a sleep lock. A non-idle relock on expiry, revocation, hook loss or disposal uses cause `release-end` and shows the lock screen. An idle lock retains its idle cause and Cover rule. [D114](../decisions/D114-bounded-delegate-unlock.md) owns the grant; `scripts/smoke/rows/lock.sh` checks ordering.

## The canonical example

Copy `watchIdle()` in `shell/plugins/vgs.lock/Service.qml`: dispose the old watch and take the owner's stage watch through the core.

## Revisit when

Hyprland changes idle-reset behavior, Quickshell can answer ScreenSaver D-Bus directly, a stage must map a window or needs cross-stage state beyond the record, panels fail to wake or stay off, or device connection wake becomes unacceptable. Revisit sleep locking if measured secure-lock time approaches logind's delay budget, and revisit hardware policy for keyboard backlights, lid-excluded outputs or gamepad-only activity.

## Not governed

Each stage's drawing and local behavior belong to its plugin. `vgs.greeter` owns pre-login actions. PAM and unlock belong to [D062](../decisions/D062-native-lock-and-polkit-plugins.md). Brightness protocol belongs to `vgs.displays/helper/brightness.py`; system-step execution belongs to [commands-are-data.md](commands-are-data.md), compositor transport to [hyprland.md](hyprland.md), and sandbox execution to [validation.md](validation.md).
