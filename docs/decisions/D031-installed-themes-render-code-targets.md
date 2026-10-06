# D031: An installed theme's curated file is dropped on a target whose files run code

[← Decision Index](INDEX.md)

**Date**: 2026-09-28
**Status**: Active
**Research**: [VGS-495](https://linear.app/vanillagreen/issue/VGS-495), the Omarchy audit attached to it; [VGS-457](https://linear.app/vanillagreen/issue/VGS-457)

**Decision**: A theme package is a directory with plugin trust: `theme.json` is the shell document, `terminal.json` holds the ANSI slots outside the token table, and a curated application file is written verbatim into the target's include path. Every target declares `runsCode`; on such a target an installed package's curated file is dropped, the template is rendered instead, and the drop is named on the apply row. No package may contribute a symlink below its own directory.

**Why**: A curated file reaches another application's include path verbatim, the same trust class as enabling plugin code. A theme has no disabled-for-review step and `theme update` fast-forwards, so an author's new code would run at the next editor start; shipped packages are reviewed with the code that ships them. `scripts/test-vgshell-targets.sh` and `bin/vgshell-theme-judge packages` hold the rule.

**Rejected**: Judging the dropped file's shape. The classification belongs beside the target, and nothing tells a copied checkout from a hand-written directory.

**Revisit when**: Packages carry signatures or a trusted-author list, or an installed theme needs a code file with no template.
