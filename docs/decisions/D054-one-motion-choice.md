# D054: One motion choice drives the shell and Hyprland

[← Decision Index](INDEX.md)

**Date**: 2026-10-08

**Status**: Active

**Research**: [VGS-1132](https://linear.app/vanillagreen/issue/VGS-1132)

**Decision**: The Motion page holds one choice for both sides: Motion on or off sets `motion.scale`, Style sets the Hyprland preset and the shell's two easings together, and Speed sets `motion.scale` as one over the speed, which scales every shell duration and every Hyprland animation speed. The one split is Window animations: whether Hyprland moves windows with that choice or keeps the user's own animations is its own switch, off by default.

**Why**: Every value the shell and Hyprland share has one meaning on both sides, so one control can set it. Hyprland alone has a second source, the animations the user's own Hyprland config sets, which the shell has no counterpart for; writing over it by default would replace the user's lines, as the earlier `vgs.themes` animation switch did not. The other values have no such source, so a split there would be two controls for one choice.

**Rejected**: A Motion control per side, which doubles every row for no difference the source shows; and one switch that always writes Hyprland's animations, which replaces the user's own.

**Revisit when**: Hyprland gains an animation value the shell cannot express, or the shell gains a motion source of the user's own.
