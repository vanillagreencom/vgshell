# Runtime: Hyprland pads

Covers: shell/Core/Pads.js, scripts/test-pads.js, scripts/smoke/rows/scratchpads.sh, shell/plugins/vgs.scratchpads/**

The Hyprland v0.56.2 and Quickshell 0.3.1 facts the layer's pads ([hyprland.md](hyprland.md), [D102](../decisions/D102-pads-tiled-in-their-special-workspace.md)) and the `vgs.scratchpads` plugin rest on, each with the source or the reading that establishes it. The other Hyprland facts are in [runtime-hyprland.md](runtime-hyprland.md).

## Showing and hiding

- In a Lua session `hyprctl dispatch <request>` evaluates `return hl.dispatch(<request>)` (`dispatchRequest` in [`src/debug/HyprCtl.cpp`](https://github.com/hyprwm/Hyprland/blob/v0.56.2/src/debug/HyprCtl.cpp)), and `hl.dispatch` runs a Lua function as it runs a dispatcher (`pushDispatcherFunction` in `src/config/lua/bindings/LuaBindingsDispatcherUtils.cpp`). So `hl.__vgs_pads.toggle("<name>","<screen>")` runs inside the eval, and the function it answers runs inside `hl.dispatch`; one that raises answers its error text, not `ok`. `src/config/lua/ConfigManager.hpp` cuts an eval at 250 ms, a dispatch at 100 ms and an event callback at 50 ms.
- `toggle_special` acts on the focused monitor (`src/config/shared/actions/ConfigActions.cpp`, lines 1114 to 1137), so the pointer's monitor decides where it shows. `HLMonitor:set_special_workspace({ workspace })` shows that special workspace on its monitor without focusing it, and with no `workspace` hides the one shown there (`monitorSetSpecialWorkspace` in `src/config/lua/objects/LuaMonitor.cpp`, lines 54 to 70). A workspace that does not exist is a no-op, and a special workspace exists only while a window is in it.
- `hl.dsp.workspace.move({ workspace = "special:<name>", monitor })` moves a hidden special workspace and its floating windows to another monitor (`src/desktop/state/WorkspacePlacementController.cpp`, lines 294 to 311). Pulling a special workspace shown on another monitor plays no In animation (`src/helpers/Monitor.cpp`, line 1653); the toggle hides a shown pad first, so it moves only a hidden one.
- An `HLMonitor` gives `width` and `height` in physical pixels, `scale`, `transform`, `x`, `y` and `reserved`, `{ top, right, bottom, left }` in logical pixels (`monitorIndex` in `LuaMonitor.cpp`). The work area in logical pixels is the size over the scale, width and height swapped for an odd `transform`, less `reserved`, as Omarchy's `default/hypr/qconsole.lua` (basecamp/omarchy `2f7302a7`) computes it.
- Focusing a window outside a shown special workspace on the same monitor hides it (`src/desktop/state/FocusState.cpp`, lines 182 to 185). A focus move to a window on another monitor does not, so the layer's `window.active` hook hides a shown pad then.

## Size and place

- A window rule's `workspace = "special:<name> silent"` maps the window into that special workspace hidden and unfocused (`src/desktop/view/Window.cpp`, lines 2324 to 2327 and 2444 to 2445). `tile = true` tiles it, and a tiled window's area is the monitor's logical box less its reserved space less the workspace rule's `gaps_out` (`src/layout/space/Space.cpp`, lines 83 to 105). The layout applies that area again on every change, so an app that resizes itself after it maps keeps the pad's size. A window rule's `size` and `move` apply once, at map (`src/layout/algorithm/floating/default/DefaultFloatingAlgorithm.cpp`, line 49).
- `hl.workspace_rule` with a workspace string already ruled changes that rule in place (`src/config/shared/workspace/WorkspaceRuleManager.cpp`, lines 25 to 32), and `gaps_out` takes `{ top, right, bottom, left }` (`src/config/lua/bindings/LuaBindingsConfigRules.cpp`, lines 204 to 206). `hl.exec_scheduled_prop_refresh_immediately()` applies new gaps in the same pass (`src/config/lua/bindings/LuaBindingsToplevel.cpp`, line 548).
- `dwindle:special_scale_factor` below 1 and `layout:single_window_aspect_ratio` shrink a lone tiled window inside that area. Both are the user's options, which the layer leaves alone.

## Motion

- Each special workspace animation reads its leaf, `specialWorkspaceIn` or `specialWorkspaceOut`, as it starts, and `hl.animation` writes the leaf at once, so a leaf set just before a show or a hide applies to it (`src/animation/WorkspaceAnimationController.cpp`, lines 55 to 134). `slide` with a side word `top`, `bottom`, `left` or `right` comes in from that side. For Out the word names the side the workspace leaves away from, so a pad that came in from the top leaves with `slide bottom`. `fade` fades.
- No per-workspace or per-window style applies to a special workspace toggle (`src/helpers/Monitor.cpp`, lines 1566, 1604 and 1654; a window rule's `animation` acts on open and close only). Each pad's motion therefore writes the two global leaves, and a special workspace of the user's own takes the motion of the last pad shown or hidden until Hyprland loads its configuration again.

## The click away

- While a special workspace is shown and `input:special_fallthrough` is off, its default, a press on that monitor outside the special workspace's windows reaches no window, changes no focus and goes to a bottom or background layer surface (`src/desktop/view/ViewHitTester.cpp`, lines 243 to 254; `src/managers/input/InputManager.cpp`, lines 896 to 911). `hl.on` has no pointer event (the event list in `src/config/lua/LuaEventHandler.cpp`), so the plugin's `background` instance takes the press.

## Events

- The event socket reports `openwindow>>ADDRESS,WORKSPACE,CLASS,TITLE`, `closewindow>>ADDRESS` and `activespecial>>WORKSPACE,MONITOR`, with an empty workspace when the monitor hides its special workspace. Quickshell 0.3.1's `Hyprland.rawEvent` delivers every line. Its `HyprlandToplevel` has no class property: `lastIpcObject` holds one only after `Hyprland.refreshToplevels()` answers, and a toplevel an `openwindow` event makes has none until the next refresh (`HyprlandIpc::onEvent` and `HyprlandIpc::refreshToplevels` in `src/wayland/hyprland/ipc/connection.cpp`). Quickshell refreshes the toplevels once as it connects and on each `configreloaded`.
- Quickshell 0.3.1's `Hyprland.toplevels` can keep a window Hyprland has closed, for the life of the shell. `closewindow` deletes the entry. A `j/clients` reply that Hyprland made before the close but Quickshell reads after it adds the entry again, and so does a late toplevel-mapping reply. `refreshToplevels` updates and adds entries but never removes one (`HyprlandIpc::refreshToplevels` and `HyprlandIpc::toplevelAddressed`, which calls `findToplevelByAddress(address, true)`, in `src/wayland/hyprland/ipc/connection.cpp`). A reader that needs the windows that exist reads `j/clients` through `Compositor.readWindows` (`Dispatch.windowState`).

## Readings

Read in `scripts/smoke/rows/scratchpads.sh` on host cachy on 2026-10-04, Hyprland v0.56.2 nested, with the toplevel helper as the pad's app:

- The first press with no app running, the helper started a second after it, read `hidden`, then `shown`, every 20 ms through the start, with one start logged, never a shown special workspace without the pad's window; the control, `toggle_special` on the pad's workspace with no window in it, read `empty`.
- The tiled window sat at its shares and anchor within 1.5 logical pixels of the work area at the sandbox's 1756 × 933 mode, at 1440 × 900 and at 3008 × 1692; under a copy of the layer that writes no gaps for the pad it filled the work area.
- Bursts of two and of three presses typed in one wtype run gave two and three `activespecial` events. Before the layer stopped recording the pad's own window as the one to give the focus back to, a burst of two gave three: `hl.dsp.focus` on a window of the hidden pad showed it again.
- After a pad with `slide` from the left showed, `animations -j` read `specialWorkspaceIn` enabled with style `slide left` and `specialWorkspaceOut` with `slide right`; after a pad with no motion, `specialWorkspaceIn` read disabled with an empty style.
- A press beside the shown pad on its monitor hid it; under a copy whose background takes no press, it stayed shown through the 5 s the real reading polls.
- A refusal from a function run through `hyprctl dispatch` makes `hyprctl` exit 7 with the error text, `vgs-pad=<key>` within it, on its output, so the compositor queue hands a caller both.
- On a headless second monitor named as the pad's screen, with the pointer on the nested output, the pad showed there; focusing a window on the nested output hid it through the layer's `window.active` hook, and without the hook it stayed shown. The headless output lists no size, so no box is read there.
- After a mode change while a pad was shown, the box fitted the new work area through the `monitor.layout_changed` hook; without the hook it kept the old one. At 3008 × 1692 and scale 2 the box sat at its shares of the logical work area.
- A pad window moved to a regular workspace came back into the pad's workspace on the next press, through the plugin's move after the toggle answered `vgs-pad=no-window`, and no second app started.
- After a hide, the keyboard went to the window focused before the show, not the one under the pointer, with or without the layer handing it back: Hyprland gives the keyboard to the window focused last on that monitor, so no control tells the layer's hand-back from Hyprland's own.
- Disabling the plugin, and removing the pad, moved its window from `special:vgs-pad-1` to the focused workspace as the layer loaded again; enabling the plugin again moved it back into the pad.
- A configuration reload while a pad is shown was not read. The new Lua state's `refit()` fits the shown pad again as it loads; the window that had the keyboard before the show is not recorded in it, so a hide after that reload hands the keyboard to no window of the layer's choosing.
