# D028: The shell writes one Hyprland Lua layer from theme and manifest data

[← Decision Index](INDEX.md)

**Date**: 2026-09-28
**Status**: Active (keyboard capture → [D067](D067-overlay-keyboard-capture.md))
**Research**: [VGS-489](https://linear.app/vanillagreen/issue/VGS-489), [VGS-585](https://linear.app/vanillagreen/issue/VGS-585), [VGS-694](https://linear.app/vanillagreen/issue/VGS-694), [VGS-695](https://linear.app/vanillagreen/issue/VGS-695), [VGS-696](https://linear.app/vanillagreen/issue/VGS-696), [VGS-744](https://linear.app/vanillagreen/issue/VGS-744), [VGS-707](https://linear.app/vanillagreen/issue/VGS-707), [VGS-924](https://linear.app/vanillagreen/issue/VGS-924)

**Decision**: The core renders one Lua file from judged manifest data and theme tokens, loaded by one `pcall(dofile, …)` line kept first in the user's `hyprland.lua` and wired only after the user consents. A plugin declares binds, layer rules and settings as data and never writes Lua. Theme appearance reaches the layer only through the bounded groups [D015](D015-tokens-are-a-judged-table.md) names, behind manifest switches owned by the first enabled declaring plugin by id. An option names a path in the closed core table and is written only while the user's `plugins` row sets it, never from a manifest default. The `hyprland` capability supplies reads of options, overrides, devices, foreign binds and the layout switch. One enabled owner of `hyprland.monitors` supplies monitor rules, including colour mode, depth and HDR levels. A display change starts as a guarded trial; a detached guard restores the captured live rules by Hyprland eval unless the user keeps it. Restore reloads configuration only when FALLBACK is the only lit output.

**Why**: Plugin text that reached Lua would run plugin code outside the shell, which [D007](D007-install-runs-no-plugin-code.md) and [D010](D010-facade-scope-not-sandbox.md) forbid. One line first keeps the user's later settings winning and leaves one thing to install, repair and remove. Writing an unset default would replace an option the user never chose to change. A closed table keeps unjudged options out. Manifest switches let Settings draw the appearance controls without a core page or a named plugin. A wrong monitor mode can blank a screen, so restore must work without user input. Eval preserves rules absent from loaded files; a reload would lose them.

**Rejected**: Plugin Lua fragments, a second monitor file and plugin-owned `hyprctl` writes. They split ownership or bypass the manifest judge. A core appearance key needs its own Settings page. A configuration reload as the normal trial restore loses rules set only by eval.

**Revisit when**: Hyprland stops running `hyprland.lua` top to bottom, drops `hl.dsp.global` or the Lua appearance functions, or a plugin needs a setting outside the closed data forms. Hyprland gains option-source or device readback, or sets monitor rules while only FALLBACK is lit so restore needs no reload.
