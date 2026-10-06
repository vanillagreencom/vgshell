# D038: First-party themes are a judged catalog in the vgs repository

[← Decision Index](INDEX.md)

**Date**: 2026-09-28
**Status**: Active
**Research**: [VGS-539](https://linear.app/vanillagreen/issue/VGS-539)

**Decision**: First-party themes live in `themes/catalog/` with one judged index. Each installs as an ordinary installed package with no curated code file, and wallpapers download on demand from pinned `vgs-themes` release archives on their own lane.

**Why**: A catalog package installs with no network, and every change reviews as a diff the judge has passed. Refusing code files keeps the trust tier of [D031](D031-installed-themes-render-code-targets.md) untouched. `bin/vgshell-theme-judge catalog-check` runs from `scripts/validate` for `themes/`.

**Rejected**: Every catalog theme as a shipped package. Install-on-demand is lost, and shipped trust would give each one curated code files.

**Revisit when**: The catalog outgrows the repository, or catalog packages need code files with no template.
