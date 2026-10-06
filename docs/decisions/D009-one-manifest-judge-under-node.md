# D009: One judge per decision, shared by the shell and the scripts under node

[← Decision Index](INDEX.md)

**Date**: 2026-09-21
**Status**: Active
**Research**: —

**Decision**: Each decision the shell and its scripts share, a manifest, the merged configuration, a theme document, a Hyprland reply, is one pure JavaScript library with no QML object and no I/O. The shell imports it, and the scripts and `vgshell` run the same file under node. Node 18 is the floor the runner's preflight checks.

**Why**: A second copy of a judge drifts even while both agree, and a pure function tests under node in milliseconds without a compositor. `scripts/test-plugin-logic.js` and `bin/lib/check-manifests.js` load the same file.

**Rejected**: Rewriting the judges into bash to drop the node dependency. The judge must be the file the shell loads.

**Revisit when**: A decision needs a QML type node cannot host, or node is unavailable on the reference machine.
