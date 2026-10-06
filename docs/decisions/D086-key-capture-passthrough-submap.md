# D086: Key capture reaches the Settings window through a Hyprland pass-through submap

[← Decision Index](INDEX.md)

**Date**: 2026-10-01
**Status**: Active
**Research**: [VGS-687](https://linear.app/vanillagreen/issue/VGS-687)
**Refines**: [D028](D028-one-generated-hyprland-layer.md), [D067](D067-overlay-keyboard-capture.md)

**Decision**: While a key field captures, Hyprland sits in a second constant core submap of the generated layer whose only bind is Escape, so every other key reaches the focused Settings window. Each way out of the submap has one owner, and the compositor owns the exits a dead or wedged shell cannot take: the window's close and a timer inside Hyprland.

**Why**: Hyprland runs a default-map bind before the focused client sees the key, so a capture must start in the compositor. A stuck submap takes every bind from the user, so the compositor must reset it without the shell. `scripts/smoke/rows/key-passthrough.sh` reads the exits back.

**Rejected**: Capturing in Qt alone. A combination a bind holds never reaches the window.

**Revisit when**: Hyprland lets a focused client receive bound keys without a submap, or Quickshell offers a key grab for application windows.
