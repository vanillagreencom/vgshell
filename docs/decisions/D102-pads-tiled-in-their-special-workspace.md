# D102: A pad is a tiled window in its own special workspace, sized by that workspace's gaps

[← Decision Index](INDEX.md)

**Date**: 2026-10-04
**Status**: Active
**Research**: [VGS-780](https://linear.app/vanillagreen/issue/VGS-780)
**Refines**: [D028](D028-one-generated-hyprland-layer.md), [D032](D032-settings-plugin-and-manifest-settings-convention.md)

**Decision**: Each pad is a tiled window in its own special workspace, sized by that workspace's `gaps_out` and toggled by one Lua call the layer defines. The plugin declares pads as data in its manifest and writes no Hyprland text, and a stranded window moves to the focused workspace at each layer load.

**Why**: A window rule's `size` and `move` apply once at map, so hand-built pads lost their geometry on each reveal, while gaps the layout reapplies hold the size whatever the application does. A toggle split across dispatches lets a pointer or focus move pick another monitor between steps. `scripts/test-pads.js` holds the rule.

**Rejected**: Per-pad window rules for size and position. They hold only at map.

**Revisit when**: Hyprland gives a special workspace its own animation style, or a second plugin needs pads of its own.
