# D044: Application windows are Hyprland toplevels, and transient overlays close on an outside click

[← Decision Index](INDEX.md)

**Date**: 2026-09-29
**Status**: Active
**Research**: [VGS-582](https://linear.app/vanillagreen/issue/VGS-582)
**Refines**: [D032](D032-settings-plugin-and-manifest-settings-convention.md)

**Decision**: Kind `window` is a Hyprland toplevel built as a Quickshell `FloatingWindow` under the shell's one app class, floated and centred by one core rule in the generated layer. Every other surface is a transient overlay that closes on an outside click.

**Why**: Only a toplevel gets Hyprland's border, focus, keybinds and rules with no VGS code imitating them. One rule on one class keeps [D028](D028-one-generated-hyprland-layer.md) and [D033](D033-floating-tuis-are-core.md) whole. `scripts/smoke/app-window.sh` reads a window's rules back.

**Rejected**: One app-id per window. Quickshell 0.3.1 and Qt 6.11.2 expose no per-window app-id, so the title names the window instead.

**Revisit when**: Quickshell gives a window its own app-id, or a plugin needs a window Hyprland must not float.
