# D011: The manifest and the plugin API are VGS's own

[← Decision Index](INDEX.md)

**Date**: 2026-09-21
**Status**: Active
**Research**: —

**Decision**: `manifest.json` is VGS's own schema with every unknown key refused, and `qs.Commons`, `qs.Ui` and the `shell` object carry VGS's own names. No translation layer, fixture or shared namespace exists for another shell's plugins; a port is a rewrite.

**Why**: One schema with one judge has no second format to drift from, and a compatibility promise nothing tests is a claim, not a contract. The first design borrowed another shell's schema, whose names had drifted in meaning while no foreign plugin had ever loaded.

**Rejected**: Another Hyprland shell's manifest schema with VGS additions under a reserved key.

**Revisit when**: A plugin marketplace with a stable, versioned schema exists that VGS gains more from joining than from owning its own.
