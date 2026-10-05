# D102: A pad is a tiled window in its own special workspace, sized by that workspace's gaps

[← Decision Index](INDEX.md)

**Date**: 2026-10-04

**Status**: Active

**Research**: [VGS-780](https://linear.app/vanillagreen/issue/VGS-780) and its plan

**Refines**: [D028](D028-one-generated-hyprland-layer.md), [D032](D032-settings-plugin-and-manifest-settings-convention.md)

**Context**: VGS-780 asks for named scratchpads: an app the owner shows and hides with one key, each pad with its own size as a share of the screen, position, entry side, motion and screen, set from Settings with no file edited. The owner's hand-built pads reasserted their geometry on every reveal, because a window rule's `size` and `move` apply once, at map. Omarchy (basecamp/omarchy `2f7302a7`, `default/hypr/qconsole.lua`) has one scratchpad, tiled in `special:scratchpad` and sized by that workspace's `gaps_out`, with one global animation and no settings. No plugin writes Hyprland configuration (D028), and a manifest's settings were flat (D032).

**Decision**:

- **The window.** Each pad's window is tiled in its own special workspace, `special:vgs-pad-<name>`, which a window rule of the generated layer maps it to, hidden and unfocused. The workspace's `gaps_out`, written from the pad's shares, anchor and margin against the work area of the monitor it shows on, sizes it; Hyprland's layout applies it again on every change. This is Omarchy's approach, per pad.
- **One Lua call.** The layer defines `hl.__vgs_pads.toggle(name, screen)`, which a plugin's `compositor` capability sends as one request. Inside Hyprland it hides a shown pad, or moves the hidden workspace to the screen, writes its gaps, sets the special workspace leaves to the pad's motion, shows it and focuses its window, so no pointer or focus move lands between the steps. It refuses a pad whose workspace holds no window.
- **Data, not plugin Lua.** A manifest's `hyprland.pads` names a schema setting of the new `list` type; the core judges each item and renders the pads, and the plugin writes no Hyprland text. The `list` type holds flat entries alone, and a pad's key is a bind `pad-<name>`, drawn in the page's Keys section like any bind.
- **No stranded window.** Each time the layer loads, a window in a pad's workspace whose pad the layer no longer holds, after the pad's removal or its plugin's disabling, moves to the focused workspace. The layer does it, since a disabled plugin runs no code that could.
- **The click away.** A click beside a shown pad reaches no window and no Lua event, so the plugin's `background` instance, shown on a screen only while a pad is shown there, takes it and hides the pad.

**Rationale**:

- Gaps the layout applies again hold a pad's size whatever the app does, where a rule's `size` holds only at map.
- A toggle split into several dispatches lets a pointer or focus move between them pick another monitor; one Lua call cannot be split.
- The core keeps its one judge of a manifest and one writer of the layer; the plugin owns the app's lifecycle, which needs the window events and a start timer.
- Per-pad motion rewrites the global `specialWorkspaceIn` and `specialWorkspaceOut` leaves, since Hyprland v0.56.2 has no per-workspace style for a special workspace ([runtime-hyprland-pads.md](../architecture/runtime-hyprland-pads.md)). A user's own special workspace takes the last pad's motion; the plugin's README names it.

**Revisit When**: Hyprland gives a special workspace its own animation style, or a second plugin needs pads of its own.

**Verification**: `node scripts/test-pads.js`, `node scripts/test-hyprland-layer.js`, `node scripts/test-dispatch.js`, `node scripts/test-plugin-logic.js` and `scripts/smoke/rows/scratchpads.sh` in the nested sandbox.

**References**: [hyprland.md](../architecture/hyprland.md), [plugin-manifest.md](../architecture/plugin-manifest.md), [runtime-hyprland-pads.md](../architecture/runtime-hyprland-pads.md), [D028](D028-one-generated-hyprland-layer.md), [D032](D032-settings-plugin-and-manifest-settings-convention.md), [D057](D057-setting-options-from-status.md).
