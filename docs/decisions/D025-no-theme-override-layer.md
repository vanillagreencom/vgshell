# D025: No user override layer merges over the applied theme

[← Decision Index](INDEX.md)

**Date**: 2026-09-28
**Status**: Active (Appearance keys → [D103](D103-appearance-values-over-the-theme.md))
**Research**: [VGS-473](https://linear.app/vanillagreen/issue/VGS-473)

**Decision**: The shell draws the applied package's document alone. A user who wants one colour changed installs an edited copy as their own package.

**Why**: A merged local file makes every colour the product of two files, and the list, the apply, the plugin and each target renderer would all have to agree on the merge.

**Rejected**: A `theme.local.json` of token overrides merged after the package. A second source for every colour. A fork button in the plugin was deferred because its result is an ordinary installed package.

**Revisit when**: Users need a local change that follows upstream updates of an installed package, or a target needs a per-user value no package can carry.
