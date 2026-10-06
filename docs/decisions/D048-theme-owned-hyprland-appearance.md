# D048: Themes own bounded Hyprland appearance groups through manifest switches

[← Decision Index](INDEX.md)

**Date**: 2026-09-29
**Status**: Active
**Research**: [VGS-585](https://linear.app/vanillagreen/issue/VGS-585)
**Refines**: [D015](D015-tokens-are-a-judged-table.md), [D028](D028-one-generated-hyprland-layer.md)

**Decision**: A theme's `hyprland` token group reaches the layer only as three fixed groups, borders, radius and motion, each behind a boolean switch a manifest's `hyprland.appearance` maps. The first enabled declaring plugin by id owns the switches, and the core names no plugin.

**Why**: Layout, gaps, blur, opacity, cursor, fonts and keybinds stay the user's. A manifest switch draws its Settings row for free under [D032](D032-settings-plugin-and-manifest-settings-convention.md) while the plugin boundary stays intact. `scripts/test-hyprland-layer.js` holds the groups.

**Rejected**: A core `shell.json` key. It would need bespoke Settings UI.

**Revisit when**: Hyprland drops the Lua appearance functions the layer uses, or a theme must set layout-affecting values.
