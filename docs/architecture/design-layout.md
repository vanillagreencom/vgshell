# A container owns one inset box

Read before touching a container's inset, a row's height, the corner-clearing rule or a component's spacing.

## The approach

Every window, dialog, panel, popover and overlay is a `Pane` from `qs.Ui`, which owns one token-driven inset box. A boxed child puts its outer box on that edge and unboxed text puts its glyphs there; each child pads itself. A scroll bar sits inside the right inset strip, a footer stays outside the scrolling body, and rectangular content under a rounded corner steps in by the clearance `shell/Commons/Inset.js` computes until it clears the curve. A list in a popover carries no inset: a row's fill meets the border, and the row's own side padding carries the text inset. The choices are [D050](../decisions/D050-container-layout-contract.md) and [D063](../decisions/D063-design-scale-on-the-4-px-grid.md).

## Why

One inset owner ends per-surface padding arithmetic, so a header, body and footer share one edge and a scroll bar's arrival never moves the layout. Content lower in a rounded container needs less inset, so clearance is computed from the radius rather than kept as a padding token. A gap of any width between a row's fill and a popover's border reads as a gutter, which is why the fill sits on the border.

## Rules

- Do compose `Pane` for every container and hand it `padding`, `cornerRadius`, `bodySpacing` and `gap` only from a plugin-owned look; never a second inset implementation. `scripts/qml-tests/tst_pane.qml` pins the box and the footer.
- Do put a boxed child's box, and unboxed text, on the inset edge; never add a second inset inside a container. `scripts/smoke/rows/manager.sh` holds every Settings field to one label edge and one control edge.
- Do clear a rounded corner through `Inset.clearing`; never hand-pad for a curve. `scripts/test-inset.js` pins the rule and `scripts/qml-tests/tst_spacing.qml` reads `Toast`.
- Do let a header's leading `IconButton` put its glyph, not its box, on the content edge; it is the one child that may reach into the inset.
- Do make every one-line control `size.control.md` tall with `control.gap` between icon and text, every row `row.paddingX` a side and one `row.height`, so metadata and setting rows align. `tst_spacing.qml` reads them under the defaults and a moved theme; `scripts/smoke/rows/manager.sh` reads every field row's height.
- Do put a group's lines in a `GroupList`; a surface states no gap and no divider colour. `scripts/qml-tests/tst_grouplist.qml` pins it.
- Do fill a popover list's rows to the border and cut the list under a rounded corner through `ListMask`; never a gutter. `scripts/qml-tests/tst_overlays.qml` reads a square and a rounded theme.
- Do size a summoned popup to `OverlayState.room`, so it fits its content up to its share of the screen and then scrolls.
- Do give form feedback as plain sentence-case text under the control; a chip, a fill or capitals only for a state the user must act on now.
- Do pair `text.label` with `text.value` in a key/value row, and use `windowTitle` for a window title and `h3` elsewhere; `h1` and `h2` are for documents.

## The canonical example

`shell/plugins/vgs.settings/PageHeader.qml`: a `Pane` header whose leading icon button puts its glyph on the edge, a title in `windowTitle`, and nothing padded twice. Copy it.

## Revisit when

A child must bleed outside the inset box, Quickshell adds a container primitive that owns the inset, the gutter and the fit, a popover list gains a header or footer, or the list mask's layer cost shows in a GPU measurement.

## Not governed

The values themselves, which are the `inset`, `row`, `stack` and `menu` groups of `shell/Commons/Tokens.js`, and the reference each value was read from, `docs/reference/design-values.md`. The components' own contract is [components.md](components.md).
