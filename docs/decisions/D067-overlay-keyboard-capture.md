# D067: Keyboard capture uses core Hyprland submaps with compositor-owned exits

[← Decision Index](INDEX.md)

**Date**: 2026-09-29
**Status**: Active
**Research**: [VGS-596](https://linear.app/vanillagreen/issue/VGS-596), [VGS-687](https://linear.app/vanillagreen/issue/VGS-687)
**Refines**: [D028](D028-one-generated-hyprland-layer.md)

**Decision**: The generated layer enters one capture submap while any `vgs:overlay` layer is mapped, repeats plugin shortcuts inside it, learns the user's focus binds by wrapping `hl.dsp.focus` and `hl.bind`, and forwards direction keys to the frontmost overlay's `navigate`. A key field uses a second constant core submap whose only bind is Escape, so every other key reaches the focused Settings window. Each exit has one owner. Hyprland owns the window-close exit and a timer that resets the pass-through submap even when the shell dies or stops answering.

**Why**: Hyprland runs global binds before the focused layer or window sees a key. A focus bind can move focus behind an overlay, and a bound combination cannot reach a key field without compositor capture. Hyprland reports Lua binds opaquely, so the binds cannot be learned by reading them back. A stuck submap takes every default bind from the user, so the compositor must reset it without the shell.

**Rejected**: Keeping capture in Qt or the layer surface alone. VGS loads into a user-owned Hyprland file, and a combination held by a global bind never reaches the focused window.

**Revisit when**: Hyprland exposes Lua dispatcher details through a stable API, submaps stop blocking default-map binds, Hyprland lets a focused client receive bound keys without a submap, or Quickshell offers a key grab for application windows.
