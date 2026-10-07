# D096: VGS writes monitor rules through one generated layer

[← Decision Index](INDEX.md)

**Date**: 2026-10-02
**Status**: Active
**Research**: [VGS-744](https://linear.app/vanillagreen/issue/VGS-744), [VGS-707](https://linear.app/vanillagreen/issue/VGS-707), [VGS-924](https://linear.app/vanillagreen/issue/VGS-924)
**Refines**: [D028](D028-one-generated-hyprland-layer.md)
**Supersedes**: the monitor half of [D080](D080-hyprland-options-rendered-from-data.md)

**Decision**: VGS writes monitor rules, the colour mode, colour depth and HDR levels included, through the one generated Hyprland layer, from the one enabled plugin that owns `hyprland.monitors`. The Displays pane applies a change as a guarded trial first: a detached guard restores the captured live rules through Hyprland eval unless the user keeps the change.

**Why**: A user expects System → Displays to set resolution, refresh rate, scale, orientation and colour. The generated layer keeps one writer for VGS data, and the user's own later `hl.monitor` line still wins. A wrong mode can blank a screen, so the restore must work with no input from the user and must not depend on a config reload.

**Rejected**: A second monitor file or plugin-written Lua. It gives monitor settings two owners and bypasses the manifest judge. A config reload as the restore path is also rejected: a reload drops a rule set by eval when no loaded file names that output. The restore reloads only when no output but FALLBACK is lit, to turn the outputs back on.

**Revisit when**: Hyprland gains an interface that sets a monitor rule and reports which rule set each field, or Hyprland applies a rule set while only FALLBACK is lit, so the restore no longer needs its reload.
