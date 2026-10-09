# One generated Hyprland layer, one dispatch queue, one key grammar

Read before touching the Hyprland layer, a manifest's `hyprland` key, a `plugins[].keys` entry, `vgshell hypr`, the `hyprland` and `monitors` capabilities, a dispatch, `Compositor` or `Dispatch.js`, a shortcut, a hold or tap shortcut, or the key capture and its submaps.

## The approach

The core renders one Lua file from judged manifest data and theme tokens, `shell/Core/HyprlandLayer.js`. [D028](../decisions/D028-one-generated-hyprland-layer.md) governs its loading line, appearance switches, explicit options and guarded monitor rules. The theme's border, radius and motion groups follow the user's Appearance values, which `Theme` resolves once ([D104](../decisions/D104-appearance-values-over-the-theme.md)). VGS edits no line of the user's files but its own loading line and a bind line the user confirms Settings may remove. A user's own later `hl.monitor` line still wins.

Every Hyprland request at run time leaves the shell through one queue, `Compositor`, and `Dispatch.js` is the one judge of its arguments. Only a state read after the reply proves a dispatcher acted. Hyprland is the only compositor ([D001](../decisions/D001-hyprland-only.md)).

A key is normalised once, by `PluginLogic.hyprlandKey` ([D059](../decisions/D059-keycodes-and-effective-shortcut-keys.md)). One conflict decision, `HyprlandLayer.resolveBinds`, is shared by every reader of a key, so a plugin reads the key it actually holds. A hold shortcut gets a release companion bind ([D071](../decisions/D071-hold-shortcuts-use-a-release-companion.md)). Full-screen overlays and key fields capture through the submaps [D067](../decisions/D067-overlay-keyboard-capture.md) governs; `shell/Core/KeyCapture.qml` is the one key-field capture owner.

## Why

Plugin text that reached Lua would run plugin code outside the shell. One line first keeps the user's own later line winning over any bind, rule or value, and leaves one thing to install, repair and remove. Writing an unset option's default would replace Hyprland's value for every option the user never touched. A user already sets outputs in `hyprland.lua`, so a second source would give two owners of one fact, and a wrong mode can blank every screen.

Hyprland answers a refused dispatcher with exit 0 and an error sentence, and answers `ok` to some requests that changed nothing, so neither the exit status nor the reply proves an effect. Each argument passes a pattern that admits no quote, backslash, space or comma, because a plugin's text would otherwise reach the compositor's own syntax.

Hyprland runs a global bind before the focused layer or window sees the key, so a capture must start in the compositor, and a submap is enterable only when a bind names it. `hyprctl binds -j` shows a Lua bind as `__lua` with a registry index, so the shell cannot learn which shortcut holds a key by reading Hyprland back; the shared conflict decision is how a plugin knows its key. A stuck submap would take every bind from the user.

## Rules

### Configuration layer

- Never write Hyprland configuration from a plugin; declare it in the manifest. `scripts/test-hyprland-layer.js` and `scripts/test-plugin-logic.js` pin the renderer and the judge.
- Do let only judged data reach the Lua text; a comment holds printable ASCII alone. `scripts/test-hyprland-layer.js` pins the comment row.
- Do write the applied theme groups and option lines inside the one `config.reloaded` callback, nowhere else. `scripts/smoke/rows/hyprland.sh` and `scripts/smoke/rows/hyprland-options.sh` pin it.
- Do write the file by rename only when its bytes change, then `hyprctl reload config-only`, which keeps monitors from resetting. `scripts/test-hyprland-layer.js` pins the steps.
- Do write `hl.monitor` only from `shell/Core/MonitorLogic.js`, after it judges the rule. The `runtime_writes_monitor_rule_once` row of `scripts/validate` pins it.
- Do map an option only to a path in `HyprlandLayer.OPTIONS`, one setting per path, with a schema entry that fits the path's type, and never write a manifest default. `scripts/test-plugin-logic.js` and `scripts/smoke/rows/hyprland-options.sh` pin both.
- Do keep the first plugin by id as owner of a conflicting key, appearance switch, option path or pad set, and report the loser as a `hyprland:` problem. `scripts/test-hyprland-layer.js` pins it.
- Do write the theme's border, radius and motion groups as `Theme.appearanceState.hyprland` says: a user's value or the theme's, or nothing where the user keeps their own Hyprland value, and window animations only once the user turns them on. Record each written group's option, so a row names the user's own line for it. `scripts/test-hyprland-layer.js` pins the bytes with no Appearance value and each state; `scripts/smoke/rows/appearance.sh` reads them back.
- Do keep `shell.qml`'s `//@ pragma AppId` equal to `HyprlandLayer.APP_WINDOW.appId`, and derive the TUI window rule's class pattern from the app-id, anchored and dot-escaped. `scripts/test-hyprland-layer.js` pins both.
- Do declare pads as manifest data and tile each pad in its own special workspace, sized by that workspace's `gaps_out`. A floating `size` or `move` rule applies once at map; the tiled layout reapplies its area when the application changes. Toggle through the layer's one Lua call, so a pointer or focus move cannot select another monitor between dispatches. Move a stranded pad to the focused workspace at each layer load. `scripts/test-pads.js` pins the data contract, and `scripts/test-hyprland-layer.js` pins the generated rules.
- Never create `hyprland.lua`, and let `wire` and `unwire` change no other byte. Do ask before wiring. `scripts/test-vgshell-hypr.sh`, `scripts/test-notice-logic.js`, `scripts/smoke/rows/hyprland-consent.sh` and `scripts/smoke/rows/hyprland-consent-decline.sh` pin them.
- Do remove a user's line only after the user confirms it, only a whole `hl.bind` line under the Hyprland directory that binds a plugin's key, through `vgshell hypr remove-bind`, and put it back only between the lines it stood between. `scripts/test-hyprland-state.js`, `scripts/test-vgshell-hypr.sh` and `scripts/smoke/rows/hyprland-options.sh` pin it.
- Do render the layer in the runner's shell only, after the first scan, the configuration and the theme are read. Gap: no check renders the layer before its inputs are read.
- Do read outputs on activation and on every monitor and `configreloaded` event, and keep `monitors` non-exclusive. `scripts/smoke/rows/monitor-outputs.sh` and `scripts/test-plugin-logic.js` pin both.
- Do turn an output off in the layer only inside a check that another output stays on; `shell/Core/MonitorLogic.js` states the Hyprland behaviour this rests on. `scripts/test-monitor-logic.js` and `scripts/smoke/rows/displays-modes.sh` pin it.

### Dispatch

- Do dispatch only through `Compositor`, build every request in `Dispatch.js` in both dialects, and judge the reply by its text. `scripts/test-dispatch.js` pins the judge and both forms, with a must-fail control per argument rule.
- Do read the compositor's state after `ok` to prove a dispatcher acted. `scripts/smoke/rows/compositor-dispatchers.sh` reads each effect back, with dropped-transport controls.
- Never let a plugin dispatch outside `Dispatch.PLUGIN_DISPATCHERS` and the capability's `togglePad`; the key pass-through requests are the core's alone. `scripts/test-dispatch.js` pins the list.
- Do read the windows that exist from Hyprland's `j/clients` reply, never from Quickshell's `Hyprland.toplevels`, which can keep a closed window; read state that must describe one moment in one `hyprctl --batch`. `scripts/test-webapps.js`, `scripts/test-tui-logic.js` and `scripts/smoke/rows/scratchpads.sh` pin it.

### Keys

- Do write a key in the grammar `PluginLogic.hyprlandKey` accepts. `scripts/test-hyprland-layer.js` pins it.
- Do take the key from the `plugins[].keys` entry, then the manifest; a list writes one bind per key, and `null` unbinds. `scripts/smoke/rows/hyprland.sh` reads it back.
- Do resolve conflicts through `HyprlandLayer.resolveBinds` everywhere; the first plugin by id keeps the key, and a lost conflict reads as null so a label never advertises a key the shell skipped. `scripts/test-hyprland-layer.js` and `scripts/qml-tests/tst_shortcutregistry.qml` pin both.
- Do start a hold only from a press on a registration with a live key; a release bind authenticates nothing, since a virtual keyboard can send one. `scripts/smoke/rows/hold-shortcuts.sh` and `tst_shortcutregistry.qml` pin it.
- Do fire a tap shortcut, a lone key, from the layer's one `input.keyboard.key` tracker behind a non-consuming gate bind, so the lock, inhibitors and submaps still apply. `scripts/test-hyprland-layer.js` and `scripts/smoke/rows/hold-shortcuts.sh` pin it.
- Do capture keys only through `shell.shortcut.capture`; a control never dispatches, and only `KeyCapture` sends the pass-through requests. `scripts/qml-tests/tst_keycapture.qml` pins it.
- Never let the pass-through's `leave` reset the overlay's `vgs:capture` submap; it resets `vgs:passthrough` alone. `scripts/test-hyprland-layer.js` and `scripts/smoke/rows/overlay-capture.sh` pin it.
- Do refuse a captured key that types text with no modifier but Shift; a bind on it stops typing everywhere. `scripts/test-key-capture.js` pins it.
- Do draw the same conflict hint in the Settings Keys row and the Key Hints window through `ShortcutField`. `scripts/test-key-capture.js` pins it.

## The canonical example

The TUI window rule section of `shell/Core/HyprlandLayer.js` for a new layer section, the `reveal` builder in `shell/Core/Dispatch.js` for a new dispatch, and `shell/Core/ShortcutRegistry.qml` for a new shortcut consumer. Copy them.

## Revisit when

Hyprland stops running `hyprland.lua` top to bottom, drops `hl.dsp.global` or the Lua appearance functions, needs a setting no data form covers, or gains an interface that sets a monitor rule and reports which rule set each field. Hyprland exposes Lua dispatcher or shortcut identity through a readback API, guarantees Lua release delivery across modifier changes, lets a focused client receive bound keys without a submap, or stops running default-map binds ahead of the focused layer. Quickshell's toplevel list removes closed windows.

## Not governed

The keyboard standard every surface meets inside its own window, which is [design-system.md](design-system.md). Each Hyprland or Quickshell behavior one piece of code works around, which is a comment at that code.
