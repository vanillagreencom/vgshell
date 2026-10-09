# D104: Appearance values sit over the theme, resolved once

[← Decision Index](INDEX.md)

**Date**: 2026-10-08

**Status**: Active

**Research**: [VGS-1132](https://linear.app/vanillagreen/issue/VGS-1132), [VGS-1133](https://linear.app/vanillagreen/issue/VGS-1133)

**Supersedes**: [D025](D025-no-theme-override-layer.md) for the Appearance keys alone: corner radius, border width, control radius, motion, fonts, the glass choice and window glass.

**Decision**: A user value may sit over the theme for the window corner radius, the window border width, the control corner radius, motion: on or off, style and speed, two fonts: the interface font and the terminal font, and VGlass: the glass choice, on or off for every glass surface over each surface's own choice, and window glass, Hyprland's windows as one such surface. Colours stay theme-only. The values live in shell.json `appearance`, which only capability `appearance` writes; a key the user has not set is Set by theme. `ThemeLogic.withAppearance` joins them to the theme's overrides, the user's winning, and resolves once in `ThemeSource`, so the Quickshell surfaces and the generated Hyprland layer ([D028](D028-one-generated-hyprland-layer.md)) read one result. Each control is one base value with fixed ratios, `ThemeLogic.APPEARANCE_RATIOS`: windows 1, flyouts 0.75, grouped window tabs 0.5, controls 1; a ratio scales a user's value only. A window value may also be the user's own Hyprland value, which leaves that layer group unwritten, and window animations stay the user's own Hyprland ones until the user turns them on. The interface font sets the family of the shell's reading text and of its capitals, `font.family.sans` and `font.family.caps`, and leaves code in the theme's fixed-width family. The terminal font is no token: `vgshell theme apply` reads it from shell.json and the kitty and Ghostty targets write it, and a follow applies the theme again when it changes. With no `appearance` key every token, every layer line and every target file is the theme's alone.

**Why**: The owner asked for a few controls with wide effect, each defaulting to the theme. A local override of shape, motion and the interface font does not have the [D025](D025-no-theme-override-layer.md) cost: no target renders these keys, so no theme target, list or apply has to agree on a merge, and the one resolver is the one place both sides read. The terminal font is the one value a target renders, and it merges with nothing: no package states a terminal font, and each of the two targets writes its font lines or none. Colours keep D025's reason, since every target renders them. Ratios keep one control from becoming a value per surface, and a ratio left off the theme's own values keeps every theme drawing as its author set it. The three `vgs.themes` switches that chose whether borders, radius and motion reach Hyprland become the Use my Hyprland value state of the same rows.

**Rejected**: A user layer of raw token overrides, which would take colours too and recreate D025's merge; a value per surface, which turns three controls into fifteen; and keeping the `vgs.themes` switches beside the new rows, two places that decide one group.

**Revisit when**: A theme target must render a value a package also states, a surface needs its own value apart from its base, or users ask to change a colour without a package.
