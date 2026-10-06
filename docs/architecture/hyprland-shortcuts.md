# One key grammar, one conflict judge, one key capture owner

Read before touching a shortcut, a manifest's `hyprland.binds`, a hold or tap shortcut, the overlay keyboard capture, the key capture pass-through, or their submaps.

## The approach

A key is written as `MOD+MOD+KEY`, normalised once by `PluginLogic.hyprlandKey`, with a keycode as lower-case `code:<n>` ([D059](../decisions/D059-keycodes-and-effective-shortcut-keys.md)). One conflict decision, `HyprlandLayer.resolveBinds`, is shared by the layer renderer, the overlay capture submap and `ShortcutRegistry`, so a plugin reads the key it actually holds. A hold shortcut gets a `<name>.release` companion bind ([D071](../decisions/D071-hold-shortcuts-use-a-release-companion.md)). Full-screen overlays capture the keyboard through one submap ([D067](../decisions/D067-overlay-keyboard-capture.md)), and a key field captures through a second, pass-through submap whose only bind is Escape ([D086](../decisions/D086-key-capture-passthrough-submap.md)); `shell/Core/KeyCapture.qml` is the one capture owner.

## Why

Hyprland runs a global bind before the focused layer or window sees the key, so a capture must start in the compositor, and a submap must be named by a bind to be enterable. A Lua bind can lose its release when the key changes the modifier mask, so a hold needs a companion that ignores modifiers, and that companion also sees unrelated releases, so the owner guards. `hl.timer` is cancelled on every reload, so the layer leaves the pass-through submap each time it loads, and a stuck submap would take every bind from the user.

## Rules

- Do write a key with `SUPER`, `CTRL`, `ALT` and `SHIFT`, and a keycode as `code:<n>` without leading zeros. `scripts/test-hyprland-layer.js` pins the grammar.
- Do take the key from the `plugins[].keys` entry, then the manifest; a list writes one bind per key, and `null` unbinds. `scripts/smoke/rows/hyprland.sh` reads it back.
- Do resolve conflicts through `HyprlandLayer.resolveBinds` everywhere; the first plugin by id keeps the key, and a lost conflict reads as null so a label never advertises a key the shell skipped. `scripts/test-hyprland-layer.js` and `scripts/qml-tests/tst_shortcutregistry.qml` pin both.
- Do give a hold shortcut a release companion with `release`, `non_consuming`, `transparent` and `ignore_mods`, and start a hold only from a down on a registration with a live key; a release bind authenticates nothing, since a virtual keyboard can trigger it. `scripts/smoke/rows/hold-shortcuts.sh` and `tst_shortcutregistry.qml` pin both.
- Do give a tap shortcut a lone key and fire it from the layer's one `input.keyboard.key` tracker: it arms only when no other key is down, any other press disarms it, and it sends the global on the release that comes before `input:repeat_delay`, allowed by a non-consuming gate bind so the lock, inhibitors and submaps still apply. Hyprland 0.56.2 has no tap bind, and its release bind fires after every chord and long hold. `scripts/test-hyprland-layer.js` and `scripts/smoke/rows/hold-shortcuts.sh` pin it.
- Do capture keys only through `shell.shortcut.capture`; a control never dispatches. Do hold a new enter until the earlier leave is answered; the `submap` event precedes the dispatch reply. `scripts/qml-tests/tst_keycapture.qml` pins both.
- Do let `leave` reset only `vgs:passthrough`, never the overlay's `vgs:capture`, and reset the capture submap only when it is the current one; the layer's close hook resets it when the shell dies. `scripts/test-hyprland-layer.js` and `scripts/smoke/rows/overlay-capture.sh` pin both.
- Do refuse a captured key that types text with no modifier but Shift; a bind on it stops typing everywhere. `scripts/test-key-capture.js` pins it.
- Do draw the same conflict hint in the Settings Keys row and the Key Hints window through `ShortcutField`. `scripts/test-key-capture.js` pins it.
- Do turn `input:resolve_binds_by_sym` on in a smoke row that types a bind through `wtype`; keys from a virtual keyboard reach no bind otherwise. `scripts/smoke/rows/notifications-keys.sh` and `clipboard.sh` carry it.

## The canonical example

`shell/Core/ShortcutRegistry.qml`: one registration per declared bind, the effective key read through the shared judges, the hold completed once, and the capture owner inside it. Copy its shape for a new shortcut consumer.

## Revisit when

Hyprland changes keycode syntax, exposes shortcut identity through a readback API, guarantees Lua release delivery across modifier changes, lets a focused client receive bound keys without a submap, or stops running default-map binds ahead of the focused layer.

## Not governed

What the rest of the layer writes, which is [hyprland.md](hyprland.md); the keyboard standard every surface meets, which is [keyboard.md](keyboard.md).
