# D080: Hyprland options are rendered from data and written only when set

[← Decision Index](INDEX.md)

**Date**: 2026-09-30
**Status**: Active (monitor rules → [D096](D096-vgs-writes-monitor-rules-through-one-generated-layer.md))
**Research**: [VGS-694](https://linear.app/vanillagreen/issue/VGS-694), [VGS-695](https://linear.app/vanillagreen/issue/VGS-695), [VGS-696](https://linear.app/vanillagreen/issue/VGS-696)
**Refines**: [D028](D028-one-generated-hyprland-layer.md)

**Decision**: A plugin asks for a Hyprland option by naming a path of a closed core table in its manifest, and the generated layer writes that option only while the user's own `plugins` row sets it, never from the manifest default. Reads of Hyprland, overrides, devices, foreign binds and a layout switch, come back through the `hyprland` capability.

**Why**: Writing an unset option's default would replace Hyprland's value for every option the user never touched and make `overridden` accuse a user's own line. A closed table keeps a plugin from setting an option VGS has not judged. `scripts/test-hyprland-layer.js` holds the table.

**Rejected**: Each plugin running `hyprctl` for its options. Every reload drops the value, plugin code writes compositor state at run time, and two plugins have nowhere to settle a conflict.

**Revisit when**: A settings plugin needs an option outside the table, or Hyprland gains an interface that lists input devices or reads an option's source.
