# D090: Core owners supply read-only input facts

[← Decision Index](INDEX.md)

**Date**: 2026-10-02
**Status**: Active
**Research**: the Jarvis plan attached to [VGS-623](https://linear.app/vanillagreen/issue/VGS-623)
**Refines**: [D059](D059-keycodes-and-effective-shortcut-keys.md), [D070](D070-jarvis-action-policy.md)

**Decision**: The core's existing device and compositor owners supply fresh key and target facts, a read-only XKB helper resolves key aliases, and Policy refuses any synthetic input whose combination could be one of the shell's own binds when held modifiers cannot be observed. A protected rectangle includes its pass-through gaps.

**Why**: Effective key strings do not resolve physical aliases, so a literal comparison misses a bind. Hyprland exposes rectangular layers but no input mask, so a gap inside a protected rectangle cannot be proven safe, and a plugin-owned reader would duplicate the core's device facts. `scripts/test-input-facts.js` holds the facts.

**Rejected**: Treating an empty part of a protected rectangle as safe. It depends on an input region the compositor does not expose.

**Revisit when**: Hyprland exposes atomic target-bound input or public protected input regions.
