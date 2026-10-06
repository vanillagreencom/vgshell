# D039: Wallpaper is per screen through an additive map that a theme apply clears

[← Decision Index](INDEX.md)

**Date**: 2026-09-28
**Status**: Active
**Research**: [VGS-544](https://linear.app/vanillagreen/issue/VGS-544), [VGS-550](https://linear.app/vanillagreen/issue/VGS-550)

**Decision**: `backgrounds.json` holds an optional `screens` map that overrides `current` per output, with no mode flag and the same schema version. A theme apply clears it, and `set` accepts only images `list --all` names.

**Why**: An absent entry is the same-everywhere state, so nothing needs seeding, and omitting the empty map keeps every existing file valid with no older-format reader. `scripts/test-vgshell-backgrounds.sh` holds the rule.

**Rejected**: A per-monitor mode flag with seeding. The flag is a second state every writer must keep in step, and seeding exists only to make it safe.

**Revisit when**: A screen needs a setting beyond its image, or an apply must keep a screen's own image.
