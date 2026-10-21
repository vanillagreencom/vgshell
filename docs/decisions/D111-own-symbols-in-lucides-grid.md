# D111: VGS draws a symbol Lucide lacks in Lucide's grid

[← Decision Index](INDEX.md)

**Date**: 2026-10-20

**Status**: Active

**Refines**: [D017](D017-templates-and-path-icons.md)

**Research**: [VGS-1953](https://linear.app/vanillagreen/issue/VGS-1953)

**Decision**: A mark Lucide does not draw, such as Jarvis's J, is VGS's own path data in `shell/Ui/icons/Own.js`, named with a `vgs-` prefix and drawn as Lucide draws: a 24 unit box, a 2 unit round stroke, ink centred. `scripts/vendor-lucide` writes one trailer into `Lucide.js` that merges `Own.ICONS` into `ICONS` and throws on a name both hold, so `Icon` and the manifest judge read an own symbol as a Lucide one. Only symbols a shipped surface draws stay in `Own.js`.

**Why**: Jarvis and Voice both drew Lucide's microphone on the bar, and Lucide has no letter or mark that names Jarvis. The manifest judge accepts only shipped icon names, so a plugin cannot bring its own; one merged set keeps D017's single drawing path and stroke token.

**Rejected**: an image file per symbol, which leaves the stroke token and the theme's icon colour, and a second icon set beside Lucide, which every reader of icons would have to learn.

**Revisit when**: Lucide ships the mark, at which point the own symbol goes, or `Own.js` grows past a handful of symbols, which would call for a sourced set instead.
