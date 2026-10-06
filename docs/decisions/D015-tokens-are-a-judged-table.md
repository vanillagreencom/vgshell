# D015: Tokens are one judged table published as frozen objects

[← Decision Index](INDEX.md)

**Date**: 2026-09-26
**Status**: Active (a plugin-owned look → [D023](D023-plugin-owned-appearance.md))
**Research**: —

**Decision**: One token table of typed leaves in `shell/Commons/Tokens.js` is the default theme. One pure judge resolves a theme document against it, under node too, and `Theme` publishes each group as a deep-frozen object with a revision counter. The grammar evaluates no JavaScript from a document. The shell bundles two variable fonts, Inter and JetBrains Mono, and a theme names font families only, never a font file.

**Why**: One table fixes each value's name and type once with no generator or generated file to review. Frozen objects make a theme change one assignment per group and a plugin write a no-op. Bundled fonts make the default theme draw the same on every machine; a system alias makes the look depend on the machine's font configuration. `scripts/check-design-tokens.py` refuses an unknown token path and a literal in shipped QML.

**Rejected**: Typed QML properties generated from the table, which answer `undefined` for a bad name at run time just as the table does and add a build step; and system font aliases such as `monospace`.

**Revisit when**: An editor resolves `qs` modules for plugin authors so typed properties would give completion, a judge needs a QML type node cannot host, or a theme package format ships font files.
