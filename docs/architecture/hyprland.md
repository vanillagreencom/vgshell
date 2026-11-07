# One generated Hyprland layer, one dispatch queue, one key grammar

Read before touching the Hyprland layer, manifest `hyprland` data, saved keys, `vgshell hypr`, compositor capabilities, dispatch, shortcuts or key capture.

## The approach

The core renders one Lua layer from judged manifest data and theme tokens through `shell/Core/HyprlandLayer.js` ([D028](../decisions/D028-one-generated-hyprland-layer.md)). `Theme` resolves Appearance values once ([D104](../decisions/D104-appearance-values-over-the-theme.md)). Hyprland is the only compositor ([D001](../decisions/D001-hyprland-only.md)); its runtime floor follows [distribution.md](distribution.md).

Runtime requests pass through the `Compositor` queue and the argument and reply judge in `Dispatch.js`. Keys use `ConfigLogic.hyprlandKey` and one conflict plan, `HyprlandLayer.resolveBinds` ([D059](../decisions/D059-keycodes-and-effective-shortcut-keys.md)). Capture belongs to the compositor submaps and `KeyCapture.qml` ([D067](../decisions/D067-overlay-keyboard-capture.md)).

## Why

Manifest text must not become executable Lua. One layer gives user configuration a defined precedence and one consent boundary. A successful transport or `ok` reply does not prove that a dispatcher changed state. Shared key resolution prevents a plugin from advertising a key it does not own.

## Rules

### Configuration layer

- Write no Hyprland configuration from a plugin. Render only judged manifest data; comments admit printable ASCII alone. `scripts/test-plugin-logic.js` and `scripts/test-hyprland-layer.js` check these boundaries.
- Apply theme groups and option values only in the layer's `config.reloaded` callback. Map only declared `HyprlandLayer.OPTIONS` paths with matching schema types, one setting per path. Never write a manifest default. `scripts/test-hyprland-layer.js` checks rendering.
- Write changed bytes by rename, then reload with `config-only`. At startup, reload an unchanged layer once only when wired and no earlier failure would be cleared. `HyprlandLayer.step` owns this decision; `scripts/test-hyprland-layer.js` checks it.
- Judge monitor rules only in `MonitorLogic.js`. Preserve the user's later `hl.monitor` precedence after Keep and reload. Turn an output off only when another stays on. `scripts/test-monitor-logic.js` checks the rule; `runtime_writes_monitor_rule_once` in `scripts/validate` checks the writer boundary.
- Keep the first plugin by id as owner of conflicting keys, appearance switches, option paths or pad sets. Report the loser as a `hyprland:` problem. `scripts/test-hyprland-layer.js` checks ownership.
- Follow `Theme.appearanceState.hyprland` for each theme group. Keep explicit user Hyprland values, opt-in window animation, window-glass enablement and glow prerequisites distinct. Record written option paths for source attribution. `scripts/test-hyprland-layer.js` checks the states.
- Use the layer's shared application-window rule and token-derived placement. Keep `shell.qml`'s AppId equal to `HyprlandLayer.APP_WINDOW.appId`; derive anchored, dot-escaped TUI class patterns from it. `scripts/test-hyprland-layer.js` checks identity and placement.
- Judge on-screen windows only through `Dispatch.onScreen` and workspace identity through `Dispatch.workspaceKey`, including Jarvis readers. Never match by display name or numeric id alone. `scripts/test-dispatch.js` and `scripts/test-jarvis-desktop.js` check identity handling.
- Declare pads as data. Tile each in its own special workspace, size by workspace gaps and toggle in one Lua call. Move stranded pads to the focused workspace on layer load. `scripts/test-pads.js` and `scripts/test-hyprland-layer.js` check the contract.
- Never create `hyprland.lua`. Ask before wiring; wire and unwire change only VGS's loading line. Remove a user bind only after confirmation, as a whole `hl.bind` line inside the Hyprland directory, through `vgshell hypr remove-bind`. Restore it only between its original neighbors. `scripts/test-vgshell-hypr.sh` checks these edit boundaries.
- Keep `bin/vgshell-share-picker`'s configuration at `$XDG_CONFIG_HOME/hypr/xdph.conf` (default `~/.config/hypr/xdph.conf`). Follow a trusted linked `hypr` folder without replacing its link, so a dotfiles checkout keeps it; refuse a link at `xdph.conf` itself. `scripts/test-share-picker.py` checks both boundaries.
- Render only in the runner's shell after scan, configuration and theme reads. A declared permission block also waits for the disk layer and permission record. Review holds readiness; `HyprlandLayer.qml` owns it.
- Read outputs on activation, monitor events and `configreloaded`. Keep capability `monitors` non-exclusive. `scripts/smoke/rows/monitor-outputs.sh` checks refresh; `PluginLogic.validateManifest` judges exclusivity.
- Hold writes and reloads during a display trial, including unsent work in an active cycle. Let an already sent reload finish. Run held work once after the trial. `scripts/test-hyprland-layer.js` checks this boundary.

### Permission authority

- Render a declared permission block once at top level: program denies before catch-all allows, then the recorder of user permission rules and related options. The first plugin by id owns it and must hold `hyprland`. `PluginLogic.hyprlandPermissionsError` judges the declaration; `HyprlandLayer.permissionLines` owns rendering.
- Enable enforcement only for the declared setting and only when the wired layer held those exact rules at Hyprland launch. Preserve the instance marker across writes. Hand wiring counts from the next sign-in. `scripts/test-hyprland-layer.js` checks admission.
- Withhold VGS rules when the executed user configuration declares permission rules or enforcement, disables virtual-keyboard process naming, or its record is unread. Report the conflict. Rules still loaded after withholding remain `withheld-loaded` until sign-in; an unwired layer writes no rules. Never claim denial is proved by the record: no check reads the denied frame back, and a client whose executable cannot be resolved can still be asked. Review holds these limits.

### Dispatch

- Dispatch only through `Compositor`. Build and validate both dialects in `Dispatch.js`, judge reply text and read state back before claiming an effect. `scripts/test-dispatch.js` checks builders and replies; `scripts/smoke/rows/compositor-dispatchers.sh` checks effects.
- Restrict plugin calls to `Dispatch.PLUGIN_DISPATCHERS`, `togglePad` and `placeWindow`. Keep key pass-through core-only. Review holds the API boundary.
- Restore native keyboard input through `Compositor.activateWindow` after intentional menu close by trigger or Escape, preserving pointer position. Outside-click dismissal changes visibility alone. An active-window record is insufficient proof of keyboard focus. `scripts/smoke/rows/bluetooth.sh` checks native input.
- Resize and restore a floating window's top-left through `placeWindow` in one batch. Read existing windows from `j/clients`, not `Hyprland.toplevels`; read state for one moment in one batch. `scripts/test-dispatch.js` checks request construction.

### Keys

- Normalize through `ConfigLogic.hyprlandKey`. Saved `plugins[].keys` take precedence over the manifest; alternatives are a list and null unbinds. `scripts/test-hyprland-layer.js` checks the grammar and plan.
- Give the user's Hyprland bind precedence over a VGS default with matching modifiers, key and submap: do not register that default. A key explicitly chosen in Settings registers as chosen, even when it matches another bind. This preserves the user's setup instead of running an unasked VGS action alongside it. Show a suppressed default's clash once, next to its existing Settings key picker, naming the user's action. Use the existing binds reader and refresh on `configreloaded`; pending or failed reads grant no new admission. `scripts/test-hyprland-layer.js` checks admission.
- Resolve ownership everywhere through `HyprlandLayer.resolveBinds`. The first plugin by id owns an exact normalized string. Merge physical and symbolic alternatives only for the same action, dispatcher and argument with equal global resolved identities; keep the physical key regardless of saved order. Other actions keep exact-string ownership, including aliases. A lost key reads as null.
- Keep the string plan when custom keymap or symbol resolution is refused. Failed reads, timeouts and malformed replies hold new admission. Wait for a new identity read only when merge pairs or the configuration-reload revision change; other key changes use the last snapshot. Advance that revision only on `configreloaded`. `HyprlandLayer.bindIdentities` owns the refusal distinction; `scripts/qml-tests/tst_hyprland_consent.qml` checks publication.
- Publish core helpers, options, rules, pads and consent before plugin-key admission. At startup over an existing layer, write nothing until admission, so failure preserves that layer and its binds. Bound the xkb helper independently of the Hyprland read, and retain an admitted object during a pending or failed replacement. `HyprlandLayer.qml` owns this boundary.
- Treat resolved identities as global facts. Public reads do not establish a per-device bind map. With per-device symbolic-resolution or keymap-file overrides, a merged symbolic alternate may not fire; the physical bind remains. Review holds this accepted limit.
- Start a hold only from a press on a live registration. A release companion grants no authority ([D071](../decisions/D071-hold-shortcuts-use-a-release-companion.md)). Track tap shortcuts through the layer's non-consuming gate so locks, inhibitors and submaps apply. `scripts/smoke/rows/hold-shortcuts.sh` checks both paths.
- Capture only through `shell.shortcut.capture`; only `KeyCapture` sends pass-through requests. Leaving pass-through must not reset overlay capture. Refuse an unmodified typing key, including Shift-only text. Use `ShortcutField` for shared conflict hints. `scripts/test-key-capture.js` and `scripts/qml-tests/tst_keycapture.qml` check these boundaries.

## The canonical example

Copy the TUI window-rule section of `HyprlandLayer.js` for layer data, the `reveal` builder in `Dispatch.js` for a request, and `ShortcutRegistry.qml` for shortcut consumption.

## Revisit when

Hyprland changes configuration order, Lua dispatch or appearance APIs, exposes effective shortcut or monitor-rule identity, guarantees release delivery across modifier changes, or lets focused clients capture bound keys without submaps. Revisit client reads when Quickshell's toplevel list reliably removes closed windows.

## Not governed

In-window input design belongs to [design-system.md](design-system.md). Local Hyprland and Quickshell constraints and their upstream sources belong beside the code that relies on them.
