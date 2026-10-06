# D050: Containers use one inset box, an inner scroll gutter and fitted popup height

[← Decision Index](INDEX.md)

**Date**: 2026-09-29
**Status**: Active
**Research**: [VGS-578](https://linear.app/vanillagreen/issue/VGS-578)

**Decision**: A `qs.Ui` container owns one token-driven inset box. Boxed children and unboxed text land on its edge, the scroll bar sits inside the right inset strip, rounded containers clear the corner by one spacing step, and dialogs and popovers fit their content up to a max-height share, then scroll.

**Why**: One inset owner ends per-surface padding drift, and a bar inside the inset keeps the left and right insets equal whether or not content overflows. `scripts/qml-tests/tst_pane.qml` and `tst_scroll.qml` hold the box.

**Rejected**: Per-surface padding arithmetic. Edges drifted, and a scroll bar could sit outside the inset.

**Revisit when**: A child must bleed outside the inset box, or Quickshell adds a container primitive owning all three.
