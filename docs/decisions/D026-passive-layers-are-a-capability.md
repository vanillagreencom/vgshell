# D026: A passive layer is a capability that draws a plugin's component on every screen

[← Decision Index](INDEX.md)

**Date**: 2026-09-28
**Status**: Active
**Research**: [VGS-476](https://linear.app/vanillagreen/issue/VGS-476), [VGS-619](https://linear.app/vanillagreen/issue/VGS-619)
**Refines**: [D005](D005-kinds-are-surfaces-no-dependencies.md), [D012](D012-core-owns-lent-objects.md)

**Decision**: `layers` is a capability, not a kind. A plugin hands the core a component, and the core draws one copy per screen on the overlay layer, never taking keyboard focus, released by a disposer or the instance's teardown. A copy declares `inputItems`, and the surface takes pointer input on the union of their rectangles; an empty list passes everything through, and `inputAll` takes the whole surface.

**Why**: A capability keeps the plugin's service the one owner of the state and the layer only its view. A surface that never takes the keyboard cannot steal a keystroke, so it can show while the user types. One bounding rectangle would steal clicks from the application in the gaps between a layer's controls, and the core notice surface already owns a region union, so one mask mechanism serves both. `scripts/smoke/rows/layers.sh` reads the copies back.

**Rejected**: A per-screen kind like `background`, which builds one instance per screen with state to reconcile; and a bounding rectangle for input.

**Revisit when**: A layer needs keyboard focus, one screen rather than every screen, a layer other than overlay, non-rectangular input, or input from an item outside its copy's tree.
