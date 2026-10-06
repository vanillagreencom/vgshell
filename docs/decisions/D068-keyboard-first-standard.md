# D068: Keyboard support is a design system standard

[← Decision Index](INDEX.md)

**Date**: 2026-09-30
**Status**: Active
**Research**: [VGS-597](https://linear.app/vanillagreen/issue/VGS-597)
**Refines**: [D054](D054-list-motion-is-one-cursor-in-qs-ui.md), [D067](D067-overlay-keyboard-capture.md)

**Decision**: Keyboard support is part of the design system. `qs.Ui` components carry it by default, one navigator owns composite key rules, hosts own Escape and initial focus, passive layers take no keys, and `scripts/check-keyboard.py` requires a marker for every exception.

**Why**: Surfaces looked complete while a keyboard user could not reach the same action or see focus. One standard replaces per-plugin audits, and host-owned focus keeps the focus reason visible, so a ring shows for key-opened surfaces only.

**Rejected**: Giving passive layers an exclusive keyboard prime. A toast could then steal typing from the active client.

**Revisit when**: Quickshell gives passive layers reliable focus without a prime, Qt changes its default button activation keys, or a surface needs a model the navigator cannot express.
