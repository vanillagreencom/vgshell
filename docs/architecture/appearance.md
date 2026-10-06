# A plugin that owns its look takes three theme inputs

Read before writing a plugin that owns its look, or touching `Theme.appearance` or its judge.

## The approach

A plugin whose design must look the same under every theme names an `appearance` library in its manifest: a `.pragma library` file exporting `TOKENS` and `LIGHT`, judged by the shell's own judge, and fed exactly three theme inputs, the mode, the accent and the motion scale. The plugin binds the judged look once and reads every value as `look.<path>`. The choice is [D023](../decisions/D023-plugin-owned-appearance.md).

## Why

Naming the two theme values the design wants as the only inputs makes a leak of any other theme value unrepresentable, and the motion scale is the reduced-motion control, not styling. A look value that equals a shipped token stays the plugin's own, so a theme that moves the shared value does not move it. Nothing infers a mode from a colour; the theme states `scheme.mode`.

## Rules

- Do declare `appearance` as a `.pragma library` file exporting `TOKENS` and `LIGHT`; `PluginLogic.validateManifest` refuses the rest, pinned by `scripts/test-plugin-logic.js`.
- Never read a `Theme` member other than `appearance` in such a plugin, and never name a path the look lacks. `scripts/check-design-tokens.py` refuses both under `theme-read` and `look-unknown`.
- Never resolve a text size below the chrome floor; `type-floor` in the same check refuses it.
- Do fail loudly on a null look; never draw what the judge refused.
- Do hand `Pane`, `SlimScrollBar` and `ListCursor` the look's own values, and read no shared spacing token.
- Do stop a non-duration animation while the motion scale is 0.

## The canonical example

`shell/plugins/vgs.launcher/Appearance.js` with `Launcher.qml`: one table, one bind, every value through `look`. Copy it.

## Revisit when

A plugin needs a third theme input, a `qs.Ui` component gains a parameterized form such plugins share, or a theme must restyle such a plugin after all.

## Not governed

The shared token table and the judge, which is [design-system.md](design-system.md).
