# D063: The design scale sits on a 4 px grid, and row heights are their own tokens

[← Decision Index](INDEX.md)

**Date**: 2026-09-30
**Status**: Active
**Research**: [VGS-580](https://linear.app/vanillagreen/issue/VGS-580), [VGS-688](https://linear.app/vanillagreen/issue/VGS-688)
**Refines**: [D015](D015-tokens-are-a-judged-table.md), [D050](D050-container-layout-contract.md)

**Decision**: Every layout dimension in the shipped token table is a multiple of 4 px, except type, strokes, indicator sizes, 2 px steps inside a component, chip padding and motion distances. Controls are 24, 32 and 40 px, and row heights are their own tokens that do not follow the control scale. A list in a popover carries no inset: a row's fill meets the border, and the row's own side padding carries the text inset.

**Why**: The reference stylesheet's 30, 7, 9 and 54 px values put neighbouring components a pixel or two apart and text off the line rhythm. Rows reading the control size would have grown every list when buttons grew. An outer inset on a popover list read as a gutter in the owner's review, and the row already pads its text for a rounded corner. `scripts/test-theme-logic.js` walks the table.

**Rejected**: Keeping the reference stylesheet's values as shipped, and an 8 px menu inset. Both showed one- and two-pixel mismatches on every surface.

**Revisit when**: The owner picks a denser or looser scale, a theme needs another grid, a popover list gains a header or footer, or the list mask's layer cost shows in a GPU measurement.
