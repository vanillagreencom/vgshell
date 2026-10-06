# Every Hyprland action goes through one dispatcher queue

Read before touching a dispatch, `Compositor`, `Dispatch.js`, or relying on what Hyprland does with a request.

## The approach

Every Hyprland request leaves the shell through `shell/Core/Compositor.qml`, one queue, built by one judge, `shell/Core/Dispatch.js`, which speaks both the Lua and the classic configuration dialect. A reply is judged by its text, because a refused dispatcher exits 0, and a dispatcher is proved to have acted only by a state read after the reply. A plugin dispatches only the operations `Dispatch.PLUGIN_DISPATCHERS` lists. Hyprland is the only compositor ([D001](../decisions/D001-hyprland-only.md)).

## Why

Hyprland v0.56.2 answers `ok` to a window move with no window and to a float toggle on an unknown action, so a reply proves nothing without a read. Its `binds -j` shows a Lua bind as `__lua` with a registry index, so a bind cannot be learned by reading it back. Each argument passes a check that admits no quote, backslash, space or comma, because a plugin's text would otherwise reach the compositor's own syntax.

## Rules

- Do dispatch only through `Compositor`, and judge the reply by text. `scripts/test-dispatch.js` pins the judge, with a must-fail control per argument rule.
- Do build every request in `Dispatch.js`, in both dialects. `scripts/test-dispatch.js` pins both forms.
- Do read the compositor's state after `ok` to prove a dispatcher acted. `scripts/smoke/rows/compositor-dispatchers.sh` reads each effect back, with dropped-transport controls.
- Never let a plugin dispatch outside `Dispatch.PLUGIN_DISPATCHERS`; the pass-through and pad requests are the core's alone. `scripts/test-dispatch.js` pins the list.
- Do run a keyboard-layout switch as its own `hyprctl switchxkblayout` argv in the same queue; it is no dispatcher, and `hyprctl dispatch switchxkblayout` is a Lua syntax error. `scripts/test-dispatch.js` holds the control.
- Do take the focused window from `activewindow` and rank the rest by `focusHistoryID` alone; it is history, not focus. `scripts/smoke/rows/compositor-reveal.sh` reads the reveal back.
- Do read `clients`, `activewindow` and `monitors` in one `--batch`, so they describe one moment, and read the windows that exist from `j/clients`; Quickshell 0.3.1's `Hyprland.toplevels` never removes an entry. `scripts/smoke/rows/scratchpads.sh` pins the read.
- Do rest the pointer off every window before a float toggle in a smoke row; under `follow_mouse` 1 the keyboard goes to the window under a resting pointer. `scripts/smoke/rows/windows.sh` pins it.
- Do read the outputs again after `configreloaded`, and hold a nested mode in a file `hyprland.lua` runs; a reload applies monitor rules before it answers and drops a rule `hyprctl eval` added. `scripts/smoke/rows/monitor-outputs.sh` and `hidpi.sh` pin both.
- Do apply the layer's option values inside `hl.on("config.reloaded")`, and write a Lua option key with underscores; a reload resets every option and `hl.device` setting before it reruns `hyprland.lua`. `scripts/test-hyprland-layer.js` and `scripts/smoke/rows/hyprland-options.sh` pin both.
- Do find where the user's configuration binds a key from the layer's own `hl.bind` wrapper, reading `debug.getinfo` on the nearest frame outside the layer: `binds -j` names no source, Hyprland v0.56.2 keeps the `debug` library but `sethook` and `gethook`, and `hl.bind` returns the bind with its `submap`, `modmask`, `key` and `keycode`. `scripts/smoke/rows/hyprland-options.sh` reads the file and line back.
- Do map a pad window tiled into its own special workspace; a floating `size` or `move` rule applies once at map, while a tiled area is reapplied on every change ([D102](../decisions/D102-pads-tiled-in-their-special-workspace.md)). `scripts/test-hyprland-layer.js` pins the rule.
- Never change a layer surface's keyboard interactivity during a held pointer press; Hyprland v0.56.2 ends the press, and Quickshell 0.3.1 applies a `WlrLayershell.keyboardFocus` change through `set_keyboard_interactivity` on the same surface (`src/wayland/wlr_layershell/surface.cpp`). `scripts/smoke/rows/placement.sh` drags bar widgets with the bar's focus unchanged.
- Never expect a press on a layer surface to enter the key pass-through submap; its enter verb refuses unless the active window's class is `org.vgs.shell` (`keyPassthroughLines` in `shell/Core/HyprlandLayer.js`), and a press on the bar changes no active window.

## The canonical example

The `reveal` builder in `shell/Core/Dispatch.js`: one batch read, the focused window from `activewindow`, a dispatch per dialect, and a bounded wait on the compositor's events before a second switch. Copy its shape for a new operation.

## Revisit when

Hyprland exposes Lua dispatcher details through a stable API, gains an interface that lists input devices or reads an option's source, or Quickshell's toplevel list removes closed windows.

## Not governed

What the generated layer writes, which is [hyprland.md](hyprland.md); the shortcut grammar and the capture submaps, which is [hyprland-shortcuts.md](hyprland-shortcuts.md).
