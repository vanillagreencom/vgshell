# D033: Floating TUIs are core, and a command is an argv list

[← Decision Index](INDEX.md)

**Date**: 2026-09-28
**Status**: Active (run end → [D043](D043-tui-run-ends-by-lock-release.md))
**Research**: the platform roadmap attached to [VGS-511](https://linear.app/vanillagreen/issue/VGS-511) § 1; [VGS-556](https://linear.app/vanillagreen/issue/VGS-556)

**Decision**: The floating terminal is core: one launcher, `bin/vgshell-tui`, knows terminals and runs a command as an argv list under the VGS presentation. A plugin opens only the scripts its manifest declares, by name with bounded arguments, and each run starts from a private copy of the plugin's whole published snapshot.

**Why**: The core itself needs a terminal before any plugin does, and an argv list keeps plugin or caller text from ever becoming shell code. A restart removes old snapshots while a script may still read its plugin's root files, so the copy holds the whole snapshot, not `tui/` alone. `scripts/test-vgshell-tui.sh` holds the copy rule; `scripts/test-tui-logic.js` pins the declarations.

**Rejected**: A string launcher into `bash -c`. Plugin text becomes shell code, and nothing ties a launch to a manifest. Links from `tui/` to root files would need two layouts.

**Revisit when**: `xdg-terminal-exec` drops `--app-id`, a TUI needs a geometry no size class covers, or a plugin ships files large enough that a copy per launch delays the window.
