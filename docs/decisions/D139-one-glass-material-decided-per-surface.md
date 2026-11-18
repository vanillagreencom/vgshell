# D139: One glass material, decided per surface, in the Glass page's style

[← Decision Index](INDEX.md)

**Date**: 2026-11-18

**Status**: Active

**Research**: [VGS-2594](https://linear.app/vanillagreen/issue/VGS-2594), approved design (comments f52e1291, fb4e4753 and 015d8e66), the owner's word through Jarvis on 2026-11-18.

**Supersedes**: [D132](D132-look-owned-glass-inputs.md). Refines [D023](D023-plugin-owned-appearance.md) and [D119](D119-plugin-look-binds-per-surface.md): a file that binds a look may also read `Theme.glassFor`.

**Decision**: `GlassSurface` is the one glass component and `shell/Commons/Glass.js` the one material table, with Dark as its base and Light and Clear as overrides. A surface names its Glass page row. `ThemeLogic.glassFor` alone decides whether glass is on for that row, its style and whether its window may show the backdrop. A surface whose inks follow a plugin-owned look takes the page's style; every other surface takes the theme's mode and the theme's raised hue. A plugin-owned look on glass picks its overrides by that style and takes the drawn glass's ground and body as inputs. A plugin hands no fill, rim, elevation or lens. Clear's faint body draws only on a material layer while the compositor's layer glass shades it; elsewhere it takes an opaque reading ground.

**Why**: Two glass paths drifted apart and cost twice the upkeep. One table and one deciding place make a style a set of values and a new surface one registry entry. Clear's white text reads over a white window only with the compositor's adaptive shading, which VGS cannot sample itself.

**Rejected**: Look-owned glass inputs ([D132](D132-look-owned-glass-inputs.md)), because each plugin kept its own material, rim and shadow. A style inferred from wallpaper luminance, because a window moving behind a card changes the ground. Clear drawn without layer glass, because its white text then falls under 4.5:1 over a light backdrop.

**Revisit when**: A surface needs a material the table's values cannot express, the compositor's layer glass changes its tone model, or a theme-ink surface needs the page's style.
