# D015: Tokens are one judged table published as frozen objects

[← Decision Index](INDEX.md)

**Date**: 2026-09-26

**Status**: Active (a plugin-owned look → [D023](D023-plugin-owned-appearance.md))

**Research**: [VGS-585](https://linear.app/vanillagreen/issue/VGS-585)

**Decision**: One token table of typed leaves in `shell/Commons/Tokens.js` is the default theme. One pure judge resolves a theme document against it, under node too, and `Theme` publishes each group as a deep-frozen object with a revision counter. The grammar evaluates no JavaScript from a document. The shell bundles two variable fonts, Inter and JetBrains Mono, and a theme names font families only, never a font file. The theme's `hyprland` group supplies borders, radius and motion only. [D028](D028-one-generated-hyprland-layer.md) owns their manifest switches and rendering into the generated layer.

**Why**: One table fixes each value's name and type once with no generator or generated file to review. Frozen objects make a theme change one assignment per group and a plugin write a no-op. Bundled fonts make the default theme draw the same on every machine; a system alias makes the look depend on the machine's font configuration. Bounded compositor appearance leaves layout, gaps, blur, opacity, cursor, fonts and keybinds with the user. `scripts/check-design-tokens.py` refuses an unknown token path and a literal in shipped QML.

**Rejected**: Typed QML properties generated from the table, which answer `undefined` for a bad name at run time just as the table does and add a build step; and system font aliases such as `monospace`.

**Revisit when**: An editor resolves `qs` modules for plugin authors so typed properties would give completion, a judge needs a QML type node cannot host, a theme package format ships font files, or a theme must set layout-affecting compositor values.
