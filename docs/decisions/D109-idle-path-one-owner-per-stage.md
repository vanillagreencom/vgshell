# D109: The idle path has one owner per stage, each on its own idle watch, and vgs.power owns energy

[← Decision Index](INDEX.md)

**Date**: 2026-10-18

**Status**: Active

**Research**: [VGS-1897](https://linear.app/vanillagreen/issue/VGS-1897): the Omarchy study (quattro at `b5f8593d`) and the comparison on that issue; [VGS-1895](https://linear.app/vanillagreen/issue/VGS-1895): the Hyprland 0.56.2 trace of idle notifications reset on window events.

**Refines**: [D062](D062-native-lock-and-polkit-plugins.md), for the core `idle` capability: it serves every stage of the idle path, not the lock alone.

**Decision**: Each stage of the idle path has one owner, with its own watch on the core `IdleRegistry` counted from the last input: dim in `vgs.displays`, the screensaver in `vgs.screensaver`, the lock and the lock before sleep in `vgs.lock`, and display off, sleep after idle, the launcher's Sleep and Hibernate rows, the power button and lid actions, wake sources, Wake on LAN and disk sleep in `vgs.power`, which keeps its id. No stage reads another stage owner's setting. Display off is one global DPMS request through a core dispatcher, and Hyprland's own input options wake the panels. Sleep goes through logind and defaults to Never. Every watch keeps `respectInhibitors: true`, and VGS accepts that Hyprland restarts those watches when a window maps, unmaps or takes focus.

**Why**: The VGS screensaver and lock are layer surfaces, which do not restart a watch, so separate watches stay correct with no cycle state; Omarchy's one monitor and timers exist because its screensaver is a window. A plugin cannot read another plugin, and counting from input gives every order of values a defined result. A global request covers both tiles of a Pro Display XDR, and a wake Hyprland performs works while the shell is down. A watch that ignores inhibitors would let a playing video dim, blank and lock the screen; the window-event restart costs a later stage after an app opens or closes a window while the user is away.

**Rejected**: Omarchy's single idle monitor with timers for the later stages, because its reason, a screensaver window, does not exist in VGS. A new `vgs.energy` plugin, because it needs `formerIds` ([D108](D108-renamed-plugin-declares-former-ids.md)) for one concern `vgs.power` already holds. Display off in `vgs.lock` or `vgs.displays`, because it is one session-wide compositor state with no per-panel backend. Watches that ignore inhibitors, a patched Hyprland, or an inhibitor reader of VGS's own to avoid the window-event restart.

**Revisit when**: Hyprland compares the inhibitor state before it resets idle notifications, the owner asks VGS to act on the window-event restart, a stage must draw a window, or a stage must know another stage's state.
