# D017: Controls extend QtQuick.Templates, and icons are Lucide path data

[← Decision Index](INDEX.md)

**Date**: 2026-09-26
**Status**: Active
**Research**: —

**Decision**: Every control of `qs.Ui` extends a `QtQuick.Templates` type and supplies only its visuals from tokens. Icons are vendored Lucide path data drawn with `QtQuick.Shapes` and scaled as an item, so the stroke width is a token. `qs.Ui` imports no Quickshell module, so every component runs offscreen under the unit runner.

**Why**: Templates give press, focus, keyboard, checked and exclusive behaviour from Qt that hand-written handlers miss. Path data lets the stroke be a token where an icon font ties it to the glyph size.

**Rejected**: `MouseArea` plus `Keys` per control, and an icon font. The first repeats Qt's work and misses keyboard paths; the second fixes the stroke to the size.

**Revisit when**: The pixel tests show a drawing defect the icon font does not have, or the resident size budget is felt.
