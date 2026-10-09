# D057: One row draws every Hyprland-mapped value

[← Decision Index](INDEX.md)

**Date**: 2026-10-08

**Status**: Active

**Research**: [VGS-1130](https://linear.app/vanillagreen/issue/VGS-1130), [VGS-1132](https://linear.app/vanillagreen/issue/VGS-1132)

**Decision**: A Settings value that maps to a Hyprland option has three states, Set by theme, the user's value and Hyprland's own, and one shared component draws them: `ValueSourceRow` in `qs.Ui`. It reads Hyprland's value, the user's own configured value and an override from what capability `hyprland` lends, names the user's own Hyprland line with Use my Hyprland value, and offers Use theme value where the theme can set the value. Mouse and the Appearance pages use it; no page draws a second form.

**Why**: The user must see in each row whether VGS, the theme or their own Hyprland config sets the value, and get back to their own config in one click. Two forms of that row drift: one names a source the other hides, or keeps the keys on an action that has hidden.

**Rejected**: A row per page, as Mouse first had, which the Appearance pages would have copied with a theme state added.

**Revisit when**: Hyprland reports which file and line set an option, so a row can name the source without the layer's recorder, or a value maps to more than one Hyprland option.
