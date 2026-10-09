# D023: A plugin may own its look, taking only the theme's mode, accent and motion scale

[← Decision Index](INDEX.md)

**Date**: 2026-09-27
**Status**: Active
**Research**: [VGS-475](https://linear.app/vanillagreen/issue/VGS-475)
**Refines**: [D015](D015-tokens-are-a-judged-table.md)

**Decision**: A plugin that names an `appearance` library in its manifest owns its look through its own token table, judged by the shell's judge, and takes only the theme's mode, accent and motion scale as inputs. The glass look, VGlass, is one shared core style: `GlassSurface` of `qs.Ui` over `Theme.glass`, which takes the same three inputs. A plugin opts into it and hands it only its own fill, rounding and elevation. The glass is the one place such a look meets shared tokens: with glass on it draws `Theme.glass`, which takes only the theme's mode, accent and motion scale; with glass off it draws the shell's standard surface, as every surface without glass does. A signature treatment, such as an edge light or a toast's spin to a circle, stays with its plugin and shows only while the glass is on.

**Why**: Naming the two theme values the design wants as the only inputs makes a leak of any other theme value unrepresentable; the motion scale is the reduced-motion control, not styling. One judge over a second table keeps every value typed and checked. `scripts/check-design-tokens.py` refuses a literal and an unknown look.

**Rejected**: A literal allowance, a plugin-id exemption or values moved into settings, each hiding the look from the judge; and a mode inferred from background luminance, which every plugin would infer differently.

**Revisit when**: A plugin needs a third theme input, a look beside the glass is shared by such plugins, or a theme must restyle such a plugin after all.
