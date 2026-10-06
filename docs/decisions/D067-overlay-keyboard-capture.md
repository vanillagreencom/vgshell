# D067: Full-screen overlays capture keyboard input through a Hyprland submap

[← Decision Index](INDEX.md)

**Date**: 2026-09-29
**Status**: Active
**Research**: [VGS-596](https://linear.app/vanillagreen/issue/VGS-596)
**Refines**: [D028](D028-one-generated-hyprland-layer.md)

**Decision**: The generated layer enters one capture submap while any `vgs:overlay` layer is mapped, repeats plugin shortcuts inside it, learns the user's focus binds by wrapping `hl.dsp.focus` and `hl.bind`, and forwards direction keys to the frontmost overlay's `navigate`.

**Why**: Hyprland runs global binds before the focused layer sees a key, so a user's move-focus keys moved focus behind an open overlay. Hyprland reports Lua binds opaquely, so the binds cannot be learned by reading them back. `scripts/smoke/rows/overlay-capture.sh` reads the submap back.

**Rejected**: Keeping the keyboard model inside the layer surface, as a shell that owns its default binds can. VGS is loaded into a user-owned Hyprland file.

**Revisit when**: Hyprland exposes Lua dispatcher details through a stable API, or submaps stop blocking default-map binds.
