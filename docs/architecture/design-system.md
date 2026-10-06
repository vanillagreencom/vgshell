# Every value the shell draws with is a token

Read before touching a token, the theme judge, `Theme`, or any value a surface draws with.

## The approach

Every colour, font, size, radius, opacity and duration a surface draws comes from one table, `shell/Commons/Tokens.js`, read as `Theme.<group>.<token>`. One pure judge, `shell/Commons/ThemeLogic.js`, resolves a theme document against that table and runs under node as well as in the shell. `Theme` publishes each group as a deep-frozen object of primitives, and a theme document is accepted whole or refused whole, so the last accepted theme stands. The component library `qs.Ui` is the only thing that turns a token into a drawn pixel. The choice is [D015](../decisions/D015-tokens-are-a-judged-table.md).

## Why

One table is the one place a value changes, so a theme that sets the palette restyles every surface in one commit. A frozen object of primitives is the only thing a plugin cannot mutate, and a QML colour's channels cannot be frozen, so colours are strings until `Theme.toColor` converts one. A judge that is a pure function lets a script run the shell's own judge, so a script and the shell cannot disagree. Whole-document refusal keeps a half-applied theme off the screen.

## Rules

- Do read every colour, font, metric, radius, opacity and duration from `Theme`. `scripts/check-design-tokens.py` refuses a literal in shipped QML under its `literal-*` rules, and an unknown `Theme` path under `token-unknown`.
- Do publish every top-level group of the table as a read-only property of `Theme`; `group-unpublished` in the same check refuses a group left out, and `scripts/smoke/rows/theme.sh` reads each group back frozen.
- Never give the table or the judge an import, a Qt object or I/O. Both are `.pragma library` files, and `scripts/test-theme-logic.js` runs them under node.
- Do make every animation read a `motion` token, so `motion.scale` 0 stills the shell; a wait that is not an animation is a `number` token. `literal-duration` refuses a literal duration.
- Do keep every length token on the 4 px grid, outside the optical classes `scripts/test-theme-logic.js` names: type, strokes, indicator sizes, 2 px steps inside a component, chip padding and motion distances. That test walks every length token: [D063](../decisions/D063-design-scale-on-the-4-px-grid.md).
- Never set a text role below the floors of the shell's own roles, 13 px for reading text and 12 px for chrome; a plugin that owns its look meets the same floor. `type-floor` in `scripts/check-design-tokens.py` reads the floor from the table.
- Do draw rest, hover, pressed, focus, disabled and checked from their own tokens, each different from rest, and never draw hover or press on an item a click cannot change. Review holds this rule; `scripts/qml-tests/tst_button.qml` and `tst_toggles.qml` pin the shipped controls.
- Do keep resting, accent and status text, control borders and selected indicators readable at the floors `ThemeLogic.readabilityShortfalls` states. `scripts/check-theme-contrast.js` runs it over the shipped theme and every catalog entry.
- Do name a font family a theme may lack, and never ship a font file in a theme; the shell bundles Inter and JetBrains Mono and falls back to the bundled family of the token's default, logged once per theme.
- Do let a plugin own its look only through an `appearance` table its manifest names, judged by the same judge and fed the theme's mode, accent and motion scale alone: [D023](../decisions/D023-plugin-owned-appearance.md). `appearance-refused`, `look-unknown` and `theme-read` in `scripts/check-design-tokens.py` refuse a table that reads anything else.
- Do land a `qs.Ui` guarantee with a test under `scripts/qml-tests/` and one mutation in `scripts/test-qml-unit.sh`; `scripts/qml-unit.sh` runs them offscreen.

## The canonical example

`shell/Ui/feedback/Badge.qml`: every value from the table, its text through the shared `Label` role, and one gallery entry per tone. Copy it.

## Revisit when

An editor resolves `qs` modules for plugin authors so typed properties would give completion, a judge needs a QML type node cannot host, or a theme package format ships font files.

## Not governed

Where a surface places its components and what it says; that is [design-layout.md](design-layout.md) and the plugin's own copy. The theme package format, apply and targets are [themes.md](themes.md).
