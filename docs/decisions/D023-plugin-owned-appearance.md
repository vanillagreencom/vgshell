# D023: A plugin may own its look, taking only the theme's mode, accent, motion scale, interface font and raised surface

[← Decision Index](INDEX.md)

**Date**: 2026-09-27
**Status**: Active (the shared system key hint uses the shell's tokens on plugin-owned surfaces too; [VGS-2180](https://linear.app/vanillagreen/issue/VGS-2180), owner-approved uniform hint pattern)
**Research**: [VGS-475](https://linear.app/vanillagreen/issue/VGS-475)
**Refines**: [D015](D015-tokens-are-a-judged-table.md)

**Decision**: A plugin that names an `appearance` library in its manifest owns its look through its own token table, judged by the shell's judge, and takes only the theme's mode, accent, motion scale, resolved interface font family (`font.family.sans`, the user's Fonts choice over the theme's) and raised surface colour (`color.surfaceRaised`) as inputs. A family the look holds at that path, or a family token that reads it, draws in the user's interface font. A look that holds no token at an input's path takes nothing from that input. The glass look, VGlass, is one shared core style: `GlassSurface` of `qs.Ui` over `Theme.glass`, which takes the same five inputs and draws its default fill in the raised surface colour. A plugin opts into it and hands it only its own fill, rounding and elevation. The glass and the shared system key hint are the places such a look meets shared tokens. With glass on it draws `Theme.glass`, which takes only those five inputs; with glass off it draws the shell's standard surface, as every surface without glass does. A signature treatment, such as an edge light or a toast's spin to a circle, stays with its plugin and shows only while the glass is on.

The shared system key hint is a second narrow shared style, as defined by [design-system.md § Components](../architecture/design-system.md#components). It uses `KeyHints` and the shell's hint tokens on every surface. All other plugin-owned drawing keeps the inputs above.

**Why**: Naming the theme values the design wants as the only inputs makes a leak of any other theme value unrepresentable; the motion scale is the reduced-motion control and the interface font is the user's reading choice, not styling. The raised surface is the fill the theme's own controls stand on, so a glass card and the theme's buttons on it share one hue. One judge over a second table keeps every value typed and checked. `scripts/check-design-tokens.py` refuses a literal and an unknown look.

**Rejected**: A literal allowance, a plugin-id exemption or values moved into settings, each hiding the look from the judge; and a mode inferred from background luminance, which every plugin would infer differently.

**Revisit when**: A plugin needs a sixth theme input, a look beside the glass is shared by such plugins, or a theme must restyle such a plugin after all.
