# D116: The core answers org.freedesktop.ScreenSaver through a helper it runs while a stage can fire

[← Decision Index](INDEX.md)

**Date**: 2026-11-03

**Status**: Active

**Research**: [VGS-2261](https://linear.app/vanillagreen/issue/VGS-2261); the logind lock: [VGS-2537](https://linear.app/vanillagreen/issue/VGS-2537) (`120b20924`), Jarvis decision 2026-11-13

**Refines**: [D012](D012-core-owns-lent-objects.md), for the bus role: the core holds `org.freedesktop.ScreenSaver` while an enabled plugin owns an idle stage that can fire, with no plugin holding a capability for it. [D109](D109-idle-path-one-owner-per-stage.md), for the idle source: it gains one pause, which holds every watch while any pause source holds.

**Decision**: `shell/Core/IdleRegistry.qml` runs `bin/vgshell-idle-inhibit`, a Python standard-library helper over `bin/lib/dbus_wire.py`, as a managed `Process` while its stage record holds a stage with a positive time. The helper asks for the name with DO_NOT_QUEUE and no replacement flag, answers `Inhibit`, `UnInhibit` and `GetActive` as hypridle does, drops a caller's cookies when the caller leaves the bus, and prints only `live` and `idle` as inhibits begin and end. While an inhibit is live, the core disables every `IdleMonitor`, which reads as input to each stage owner; enabled again, each watch counts from the pause's end. A name another connection owns is logged once and left in place, and after the helper ends the core starts it again only when the stage record goes from no stage that can fire to one. `IdleRegistry.qml` also holds one logind `what=idle` lock while the pause holds, through a Stay awake hold or a ScreenSaver inhibit, and while a Wayland inhibitor Hyprland honours holds; [power.md § Idle source and stages](../architecture/power.md#idle-source-and-stages) states the rule.

**Why**: Firefox 159 asks `org.freedesktop.ScreenSaver` first and stops at the first bus answer, and Chromium 156 asks it beside its Wayland inhibitor; on px13 neither browser held a Wayland inhibitor, so a playing video held nothing. Quickshell 0.3.1 cannot export a D-Bus object, the gap [D085](D085-bluetooth-agent-core-lent-over-bluetoothctl.md) names, so a separate process owns the name. VGS already ships Python and a D-Bus wire reader in `bin/vgshell-scan`, which the helper now shares. A disabled monitor holds no notification, so the pause needs no per-watch state. Holding the role only while a stage can fire keeps the name free for a user's own idle daemon when VGS idles nothing. VGS reports the session idle to logind, and that report arms the host's `IdleAction`, so without the lock logind's `IdleAction` acts through a hold that pauses every VGS stage.

**Rejected**: A gate per stage owner that swallows idle events or recreates watches at release, which needs re-arm state per watch. A Hyprland `idle_inhibit` window rule, which covers full screen only, one app class at a time. Patching the engine to export D-Bus objects, which is far larger than one name. A `python-dbus` or `python-gobject` dependency for what the standard library covers. A Wayland idle inhibitor on a core layer surface, which needs a surface, its map state and its lifetime only to tell Hyprland what the core can do itself.

**Revisit when**: Quickshell can export a D-Bus object, so the core answers the name itself; a browser asks only through `org.freedesktop.PowerManagement`, the portal's `Inhibit` or logind; or Hyprland honours bus inhibits on its own.
