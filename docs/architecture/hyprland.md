# One generated Hyprland layer, one dispatch queue, one key grammar

Read before touching the Hyprland layer, a manifest's `hyprland` key, a `plugins[].keys` entry, `vgshell hypr`, the `hyprland` and `monitors` capabilities, a dispatch, `Compositor` or `Dispatch.js`, a shortcut, a hold or tap shortcut, or the key capture and its submaps.

## The approach

The core renders one Lua file from judged manifest data and theme tokens, `shell/Core/HyprlandLayer.js`, loaded by one `pcall(dofile, …)` line kept first in the user's `hyprland.lua` and wired only after the user consents. A plugin declares binds, layer rules, appearance switches, input options, pads and the Displays monitor rules as data in its manifest and never writes Lua. An option reaches the layer only while the user's own `plugins` row sets it, never from a manifest default. VGS edits no line of the user's files but its own loading line and a bind line the user confirms Settings may remove. A monitor rule reaches the layer only from `vgs.displays` settings, after a guarded trial; a user's own later `hl.monitor` line still wins. The choices are [D028](../decisions/D028-one-generated-hyprland-layer.md), [D048](../decisions/D048-theme-owned-hyprland-appearance.md), [D080](../decisions/D080-hyprland-options-rendered-from-data.md) and [D096](../decisions/D096-vgs-reads-outputs-and-writes-no-monitor-rule.md).

Every Hyprland request at run time leaves the shell through one queue in `shell/Core/Compositor.qml`. `shell/Core/Dispatch.js` builds each request in both the Lua and the classic configuration dialect and is the one judge of its arguments; `Compositor` judges each reply by its text, and only a state read after the reply proves a dispatcher acted. A plugin dispatches only the operations `Dispatch.PLUGIN_DISPATCHERS` lists. Hyprland is the only compositor ([D001](../decisions/D001-hyprland-only.md)).

A key is written as `MOD+MOD+KEY`, normalised once by `PluginLogic.hyprlandKey`, with a keycode as lower-case `code:<n>` ([D059](../decisions/D059-keycodes-and-effective-shortcut-keys.md)). One conflict decision, `HyprlandLayer.resolveBinds`, is shared by the layer renderer, the overlay capture submap and `ShortcutRegistry`, so a plugin reads the key it actually holds. A hold shortcut gets a `<name>.release` companion bind ([D071](../decisions/D071-hold-shortcuts-use-a-release-companion.md)). Full-screen overlays capture the keyboard through one submap ([D067](../decisions/D067-overlay-keyboard-capture.md)), and a key field captures through a second, pass-through submap whose only bind is Escape ([D086](../decisions/D086-key-capture-passthrough-submap.md)); `shell/Core/KeyCapture.qml` is the one capture owner.

## Why

Plugin text that reached Lua would run plugin code outside the shell. One line first keeps the user's own later line winning over any bind, rule or value, and leaves one thing to install, repair and remove. Writing an unset option's default would replace Hyprland's value for every option the user never touched. A user already sets outputs in `hyprland.lua`, so a second source would give two owners of one fact, and a wrong mode can blank every screen.

Hyprland answers a refused dispatcher with exit 0 and an error sentence, and answers `ok` to some requests that changed nothing, so neither the exit status nor the reply proves an effect. Each argument passes a pattern that admits no quote, backslash, space or comma, because a plugin's text would otherwise reach the compositor's own syntax.

Hyprland runs a global bind before the focused layer or window sees the key, so a capture must start in the compositor, and a submap is enterable only when a bind names it. `hyprctl binds -j` shows a Lua bind as `__lua` with a registry index, so the shell cannot learn which shortcut holds a key by reading Hyprland back; the shared conflict decision is how a plugin knows its key. A stuck submap would take every bind from the user.

## Rules

### Configuration layer

- Never write Hyprland configuration from a plugin; declare it in the manifest. `scripts/test-hyprland-layer.js` and `scripts/test-plugin-logic.js` pin the renderer and the judge.
- Do let only judged data reach the Lua text; a comment holds printable ASCII alone. `scripts/test-hyprland-layer.js` pins the comment row.
- Do write the applied theme groups and option lines inside the one `config.reloaded` callback, nowhere else; a reload resets every option and `hl.device` setting, and Hyprland runs the callback at the end of every load, the first included. `scripts/smoke/rows/hyprland.sh` and `scripts/smoke/rows/hyprland-options.sh` read the loaded layer back.
- Do write the file by rename only when its bytes change, then `hyprctl reload config-only`, which keeps monitors from resetting. `scripts/test-hyprland-layer.js` pins the steps.
- Do write `hl.monitor` only from `shell/Core/MonitorLogic.js`, after it judges the rule. The `runtime_writes_monitor_rule_once` row of `scripts/validate` refuses a second shipped renderer, with controls in `scripts/test-validate.sh`.
- Do map an option only to a path in `HyprlandLayer.OPTIONS`, one setting per path, with a schema entry that fits the path's type, and never write a manifest default. `scripts/test-plugin-logic.js` and `scripts/smoke/rows/hyprland-options.sh` pin both.
- Do keep the first plugin by id as owner of a conflicting key, appearance switch, option path or pad set, and report the loser as a `hyprland:` problem. `scripts/test-hyprland-layer.js` pins it.
- Do keep `shell.qml`'s `//@ pragma AppId` equal to `HyprlandLayer.APP_WINDOW.appId`, and derive the TUI window rule's class pattern from the app-id, anchored and dot-escaped. `scripts/test-hyprland-layer.js` pins both.
- Do map a pad window tiled into its own special workspace; a floating `size` or `move` rule applies once at map, while a tiled area is reapplied on every change ([D102](../decisions/D102-pads-tiled-in-their-special-workspace.md)). `scripts/test-hyprland-layer.js` pins the rule.
- Never create `hyprland.lua`; `wire` and `unwire` change no other byte and keep a symlink and its target's mode. Do ask before wiring, and let Not now hold for the running Hyprland session alone. `scripts/test-vgshell-hypr.sh`, `scripts/test-notice-logic.js` and the consent smoke rows pin them.
- Do remove a user's line only after the user confirms it, only a whole `hl.bind` line under the Hyprland directory that binds a plugin's key, through `vgshell hypr remove-bind`, and put it back only between the lines it stood between. `scripts/test-hyprland-state.js`, `scripts/test-vgshell-hypr.sh` and `scripts/smoke/rows/hyprland-options.sh` pin it.
- Do render the layer in the runner's shell only, after the first scan, the configuration and the theme are read.
- Do read outputs on activation and on every monitor and `configreloaded` event, and keep `monitors` non-exclusive. `scripts/smoke/rows/monitor-outputs.sh` and `scripts/test-plugin-logic.js` pin both.

### Dispatch

- Do dispatch only through `Compositor`, build every request in `Dispatch.js` in both dialects, and judge the reply by its text. `scripts/test-dispatch.js` pins the judge and both forms, with a must-fail control per argument rule.
- Do read the compositor's state after `ok` to prove a dispatcher acted. `scripts/smoke/rows/compositor-dispatchers.sh` reads each effect back, with dropped-transport controls.
- Never let a plugin dispatch outside `Dispatch.PLUGIN_DISPATCHERS` and the capability's `togglePad`; the key pass-through requests are the core's alone. `scripts/test-dispatch.js` pins the list.
- Do read the windows that exist from Hyprland's `j/clients` reply, through `shell.compositor.readWindows` or a `Dispatch.js` batch read, never from Quickshell's `Hyprland.toplevels`, which can keep a closed window; read state that must describe one moment in one `hyprctl --batch`. `scripts/test-webapps.js` and `scripts/test-tui-logic.js` hold a control that reads the stale list, and `scripts/smoke/rows/scratchpads.sh` pins the read.

### Keys

- Do write a key with `SUPER`, `CTRL`, `ALT` and `SHIFT`, and a keycode as `code:<n>` without leading zeros. `scripts/test-hyprland-layer.js` pins the grammar.
- Do take the key from the `plugins[].keys` entry, then the manifest; a list writes one bind per key, and `null` unbinds. `scripts/smoke/rows/hyprland.sh` reads it back.
- Do resolve conflicts through `HyprlandLayer.resolveBinds` everywhere; the first plugin by id keeps the key, and a lost conflict reads as null so a label never advertises a key the shell skipped. `scripts/test-hyprland-layer.js` and `scripts/qml-tests/tst_shortcutregistry.qml` pin both.
- Do start a hold only from a press on a registration with a live key; a release bind authenticates nothing, since a virtual keyboard can send one. `scripts/smoke/rows/hold-shortcuts.sh` and `tst_shortcutregistry.qml` pin it.
- Do fire a tap shortcut, a lone key, from the layer's one `input.keyboard.key` tracker behind a non-consuming gate bind, so the lock, inhibitors and submaps still apply. `scripts/test-hyprland-layer.js` and `scripts/smoke/rows/hold-shortcuts.sh` pin it.
- Do capture keys only through `shell.shortcut.capture`; a control never dispatches, and only `KeyCapture` sends the pass-through requests. `scripts/qml-tests/tst_keycapture.qml` pins it.
- Never let the pass-through's `leave` reset the overlay's `vgs:capture` submap; it resets `vgs:passthrough` alone. `scripts/test-hyprland-layer.js` and `scripts/smoke/rows/overlay-capture.sh` pin it.
- Do refuse a captured key that types text with no modifier but Shift; a bind on it stops typing everywhere. `scripts/test-key-capture.js` pins it.
- Do draw the same conflict hint in the Settings Keys row and the Key Hints window through `ShortcutField`. `scripts/test-key-capture.js` pins it.

## The canonical example

The TUI window rule section of `shell/Core/HyprlandLayer.js`: data in, one judged class pattern, one rule per size class, pinned byte for byte by `scripts/test-hyprland-layer.js`. Copy its shape for a new section. For a new dispatch, copy the `reveal` builder in `shell/Core/Dispatch.js`: one batch read, a request per dialect, and a bounded wait on the compositor's events. For a new shortcut consumer, copy `shell/Core/ShortcutRegistry.qml`: one registration per declared bind, its key read through the shared conflict decision.

## Revisit when

Hyprland stops running `hyprland.lua` top to bottom, drops `hl.dsp.global` or the Lua appearance functions, needs a setting no data form covers, or gains an interface that sets a monitor rule and reports which rule set each field. Hyprland exposes Lua dispatcher or shortcut identity through a readback API, guarantees Lua release delivery across modifier changes, lets a focused client receive bound keys without a submap, or stops running default-map binds ahead of the focused layer. Quickshell's toplevel list removes closed windows.

## Not governed

The keyboard standard every surface meets inside its own window, which is [design-system.md](design-system.md). Each Hyprland or Quickshell behavior one piece of code works around, which is a comment at that code.
