# D071: Hold shortcuts complete through a release companion

[← Decision Index](INDEX.md)

**Date**: 2026-09-30
**Status**: Active
**Research**: [VGS-615](https://linear.app/vanillagreen/issue/VGS-615)
**Refines**: [D012](D012-core-owns-lent-objects.md), [D028](D028-one-generated-hyprland-layer.md)

**Decision**: A manifest bind with `hold: true` gets a modifier-independent, non-consuming, transparent `<name>.release` companion under the same disposer, and the owner completes only a hold its own key-down started.

**Why**: A Lua global bind can miss the release when the key changes the modifier mask or the modifier lifts first, which would leave push-to-talk active. A release bind that ignores modifiers also sees unrelated releases, so the owner must guard. `scripts/smoke/rows/hold-shortcuts.sh` reads the pair back.

**Rejected**: A consuming release bind. It can swallow a plain key before the plugin has started a hold.

**Revisit when**: Hyprland guarantees Lua release delivery across modifier changes, or its protocol supplies an input identity that needs another owner.
