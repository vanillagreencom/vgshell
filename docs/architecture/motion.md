# One cursor per list

Read before touching a list's highlight, a row's entrance, a `motion.list` token, or how hover and keys share a list's selection.

## The approach

Every list of selectable rows has one `ListCursor` from `qs.Ui`: one plate that travels between rows, with rows that rise in through `ListEntrance`, timed by the `motion.list` tokens. The keyboard writes the selection and the pointer borrows it. A plugin that owns its look hands the cursor its own timings and plate. The choice is [D054](../decisions/D054-list-motion-is-one-cursor-in-qs-ui.md).

## Why

Two highlights, a hover fill beside a keyboard highlight, came from each list drawing its own. A hover takes the selection only after the pointer has moved, so a list that scrolls or animates under a resting pointer never steals the keyboard's selection. A `ListView` highlight takes no easing and menus lay rows out in a `Column`, so the plate is a component, not a view feature.

## Rules

- Do give a list of selectable rows one `ListCursor` and let rows enter through `ListEntrance`; never a per-row hover fill beside it. `scripts/qml-tests/tst_listcursor.qml` and `tst_overlays.qml` pin it, with one mutation each in `scripts/test-qml-unit.sh`.
- Never give a cursor to a list whose highlight marks a state, or whose rows are rows of controls.
- Do declare the cursor in an item that paints nothing; it draws under the rows, and logs an error for a parent that paints a fill.
- Do call `snap()` before an opening or a rebuild sets the selection, `disarm()` on a keyboard step, a rebuild or a filter, and `arm()` to let the next hover take the plate at once. `tst_listcursor.qml` pins each.
- Do let a pick list move its selection on hover and a navigation list keep it.
- Do take every timing from a token; a plugin-owned look hands its own table in the shape of `motion.list`. `literal-duration` in `scripts/check-design-tokens.py` refuses a literal.
- Do land every step at once at `motion.scale` 0. `scripts/smoke/rows/list-motion.sh` reads it, and catches the cursor mid-travel under a slowed scale to prove the reader sees motion.

## The canonical example

The Settings plugin list, `shell/plugins/vgs.settings/`: one cursor declared in a non-painting item, rows that name it, and the keyboard and the pointer sharing one selection. Copy it.

## Revisit when

A list needs more than one selection plate, or Qt Quick gains a view highlight that takes an easing curve.

## Not governed

The launcher's own curves, slide and edge light, which its appearance table owns under [D023](../decisions/D023-plugin-owned-appearance.md).
