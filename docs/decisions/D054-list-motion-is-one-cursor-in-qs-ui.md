# D054: The list motion is one cursor in qs.Ui

[← Decision Index](INDEX.md)

**Date**: 2026-09-29
**Status**: Active
**Research**: [VGS-579](https://linear.app/vanillagreen/issue/VGS-579)
**Refines**: [D023](D023-plugin-owned-appearance.md)

**Decision**: `qs.Ui` owns the list cursor and the row entrance. Every list wires its rows to one cursor, and a plugin that owns its look passes its own timings and plate.

**Why**: Two highlights, a hover fill beside a keyboard highlight, came from each list drawing its own. A parameterized component keeps D023's promise that a look-owning plugin's values come from its own table. `scripts/qml-tests/tst_listcursor.qml` holds the cursor.

**Rejected**: A `ListView` `highlight`. Its follow animation takes no easing, and menus lay rows out in a `Column`, not a view.

**Revisit when**: A list needs more than one selection plate, or Qt Quick gains a view highlight that takes an easing curve.
