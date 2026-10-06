# D028: The shell writes one Hyprland Lua layer from theme and manifest data

[← Decision Index](INDEX.md)

**Date**: 2026-09-28
**Status**: Active (appearance → [D048](D048-theme-owned-hyprland-appearance.md); options → [D080](D080-hyprland-options-rendered-from-data.md); overlay capture → [D067](D067-overlay-keyboard-capture.md))
**Research**: [VGS-489](https://linear.app/vanillagreen/issue/VGS-489)

**Decision**: The core renders one Lua file from judged manifest data and theme tokens, loaded by one `pcall(dofile, …)` line kept first in the user's `hyprland.lua` and wired only after the user consents. A plugin declares binds and layer rules as data and never writes Lua.

**Why**: Plugin text that reached Lua would run plugin code outside the shell, which [D007](D007-install-runs-no-plugin-code.md) and [D010](D010-facade-scope-not-sandbox.md) forbid. One line first keeps the user's own settings winning and leaves one thing to install, repair and remove. `scripts/test-hyprland-layer.js` holds the renderer; `scripts/smoke/rows/hyprland.sh` reads the loaded layer back.

**Rejected**: Each plugin shipping a Lua fragment. Plugin-authored code would run in the compositor's configuration.

**Revisit when**: Hyprland stops running `hyprland.lua` top to bottom or drops `hl.dsp.global`, or a plugin needs a Hyprland setting no data form covers.
