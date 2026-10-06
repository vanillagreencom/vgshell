# D035: A manifest declares the external commands a plugin runs, and the core probes and reports them

[← Decision Index](INDEX.md)

**Date**: 2026-09-28
**Status**: Active
**Research**: [VGS-520](https://linear.app/vanillagreen/issue/VGS-520), the platform roadmap attached to [VGS-511](https://linear.app/vanillagreen/issue/VGS-511) § 3
**Refines**: [D007](D007-install-runs-no-plugin-code.md)

**Decision**: A manifest's `requirements` lists commands with a package per manager. The scan probes each once and reports the missing ones; the requirement notice is the one install path, and a plugin may offer only its declared commands.

**Why**: A requirement is a fact about the system, never another plugin, so [D005](D005-kinds-are-surfaces-no-dependencies.md) holds. One probe in the scan costs no process per plugin. `scripts/test-vgshell-scan.py` and `scripts/test-notice-logic.js` hold the probe and the notice.

**Rejected**: A plugin-to-plugin dependency key. It brings a load order and a plugin that breaks when another is disabled.

**Revisit when**: A plugin needs a requirement that is not a command on PATH, or a real command cannot be declared under an undotted name.
