# One generated Hyprland layer, and no plugin writes Hyprland configuration

Read before touching the Hyprland layer, a manifest's `hyprland` key, a `plugins[].keys` entry, `vgshell hypr`, or the `hyprland` and `monitors` capabilities.

## The approach

The core renders one Lua file from judged manifest data and theme tokens, `shell/Core/HyprlandLayer.js`, loaded by one `pcall(dofile, …)` line kept first in the user's `hyprland.lua` and wired only after the user consents. A plugin declares binds, layer rules, appearance switches, input options and pads as data in its manifest and never writes Lua. An option reaches the layer only while the user's own `plugins` row sets it, never from a manifest default. VGS edits no line of the user's files but its own loading line and a bind line the user confirms Settings may remove, and writes no monitor rule: it reads the outputs Hyprland lists through the shared `monitors` capability. The choices are [D028](../decisions/D028-one-generated-hyprland-layer.md), [D048](../decisions/D048-theme-owned-hyprland-appearance.md), [D080](../decisions/D080-hyprland-options-rendered-from-data.md) and [D096](../decisions/D096-vgs-reads-outputs-and-writes-no-monitor-rule.md).

## Why

Plugin text that reached Lua would run plugin code outside the shell. One line first keeps the user's own later line winning over any bind, rule or value, and leaves one thing to install, repair and remove. Writing an unset option's default would replace Hyprland's value for every option the user never touched. A user already sets outputs in `hyprland.lua`, so a second source would give two owners of one fact, and a wrong mode can blank every screen.

## Rules

- Never write Hyprland configuration from a plugin; declare it in the manifest. `scripts/test-hyprland-layer.js` and `scripts/test-plugin-logic.js` pin the renderer and the judge.
- Do let only judged data reach the Lua text; a comment holds printable ASCII alone. `scripts/test-hyprland-layer.js` pins the comment row.
- Do write the applied theme groups and option lines inside the one `config.reloaded` callback, nowhere else; Hyprland runs it at the end of every load, the first included. `scripts/smoke/rows/hyprland.sh` reads the loaded layer back.
- Do write the file by rename only when its bytes change, then `hyprctl reload config-only`, which keeps monitors from resetting. `scripts/test-hyprland-layer.js` pins the steps.
- Never write an `hl.monitor` line from any shipped file. The `runtime_writes_no_monitor_rule` row of `scripts/validate` refuses one, with controls in `scripts/test-validate.sh`.
- Do map an option only to a path in `HyprlandLayer.OPTIONS`, one setting per path, with a schema entry that fits the path's type, and never write a manifest default. `scripts/test-plugin-logic.js` and `scripts/smoke/rows/hyprland-options.sh` pin both.
- Do keep the first plugin by id as owner of a conflicting key, appearance switch, option path or pad set, and report the loser as a `hyprland:` problem. `scripts/test-hyprland-layer.js` pins it.
- Do keep `shell.qml`'s `//@ pragma AppId` equal to `HyprlandLayer.APP_WINDOW.appId`, and derive the TUI window rule's class pattern from the app-id, anchored and dot-escaped. `scripts/test-hyprland-layer.js` pins both.
- Never create `hyprland.lua`; `wire` and `unwire` change no other byte and keep a symlink and its target's mode. Do ask before wiring, and let Not now hold for the running Hyprland session alone. `scripts/test-vgshell-hypr.sh`, `scripts/test-notice-logic.js` and the consent smoke rows pin them.
- Do remove a user's line only after the user confirms it, only a whole `hl.bind` line under the Hyprland directory that binds a plugin's key, through `vgshell hypr remove-bind`, and put it back only between the lines it stood between. `scripts/test-hyprland-state.js`, `scripts/test-vgshell-hypr.sh` and `scripts/smoke/rows/hyprland-options.sh` pin it.
- Do render the layer in the runner's shell only, after the first scan, the configuration and the theme are read.
- Do read outputs on activation and on every monitor and `configreloaded` event, and keep `monitors` non-exclusive. `scripts/smoke/rows/monitor-outputs.sh` and `scripts/test-plugin-logic.js` pin both.

## The canonical example

The TUI window rule section of `shell/Core/HyprlandLayer.js`: data in, one judged class pattern, one rule per size class, pinned byte for byte by `scripts/test-hyprland-layer.js`. Copy its shape for a new section.

## Revisit when

Hyprland stops running `hyprland.lua` top to bottom, drops `hl.dsp.global` or the Lua appearance functions, needs a setting no data form covers, or gains an interface that sets a monitor rule and reports which rule set each field.

## Not governed

How a request is dispatched and judged, which is [runtime-hyprland.md](runtime-hyprland.md); the shortcut grammar and the capture submaps, which is [hyprland-shortcuts.md](hyprland-shortcuts.md).
