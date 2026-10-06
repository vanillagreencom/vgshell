# A flow that asks the user runs in a floating terminal

Read before touching a floating TUI, `bin/vgshell-tui`, the `tui` capability, a TUI's exit record, or any flow that asks the user a question or a password.

## The approach

A flow that asks the user anything, a password, a y/N, runs in a floating terminal the user sees, never inside the shell process, and the terminal outlives the shell. One launcher, `bin/vgshell-tui`, knows terminals, runs the command as an argv list under the VGS presentation, and picks a size class, never a geometry. The presenter, the only process that knows when the command ended, writes the run's record under a new name per state, and the core learns the end by blocking on the run's own lock ([D043](../decisions/D043-tui-run-ends-by-lock-release.md)), never by polling a process. A plugin's script runs from a private copy of its whole published snapshot. The choice is [D033](../decisions/D033-floating-tuis-are-core.md).

## Why

A password typed into the shell process would be a secret in a QML field, a log or IPC; a terminal the user sees is the one place a prompt can be answered. A single-instance terminal starts the presenter from a process already running, so the launcher's exit says nothing about the run, and `FolderListModel` can miss a change under load. A restart removes old snapshots while a script may still read its plugin's root files. Whether a terminal floats depends only on its desktop entry's `X-TerminalArgAppId` key; VGS chooses no terminal.

## Rules

- Do launch every asking flow through `bin/vgshell-tui`, hand `present` everything it needs in argv, and never pass a command through a shell. `scripts/test-vgshell-tui.sh` pins it with a control that runs `bash -c`.
- Do fork the terminal with `setsid -f`; Quickshell kills its children when the shell stops, and a restart during an install must not kill the install. `scripts/test-vgshell-tui.sh` pins it.
- Do strip `VGSHELL_RUNNER_PID` from the terminal's environment; a single-instance terminal hands it to later windows, and `vgshell pkg run` refuses it. `scripts/test-vgshell-tui.sh` pins it.
- Never source `gum.env`; parse it, and one bad line exports nothing. Put the Done or Failed prompt on `/dev/tty`, not stdout. `scripts/test-vgshell-tui.sh` pins both.
- Do write a record whole under a hidden name and rename it; never rewrite one, a new state is a new file, and never let the command inherit the key lock or the run lock. `scripts/test-vgshell-tui.sh` pins each.
- Do treat the directory listing as the fast path and the wait on the run lock as the completion guarantee; never start two waits for one run. `scripts/qml-tests/tst_tui_records.qml` and `scripts/test-tui-logic.js` pin both.
- Do keep a key's last ended record across a shell restart. `scripts/test-vgshell-tui.sh` pins it.
- Do hold one sudo session per script; a nested session joins a live owner. `scripts/test-tui.sh` pins it with a stand-in `sudo`.
- Do pick a size class from `HyprlandLayer.TUI_WINDOWS` in `shell/Core/HyprlandLayer.js`, never a geometry.

## The canonical example

The `log` TUI of `shell/plugins/vgs.updates/`: one declared script, opened by name, the plain presentation. Copy it.

## Revisit when

`xdg-terminal-exec` drops `--app-id`, gum changes its environment names, a TUI needs a geometry no size class covers, or Qt fixes the lost directory-change wake and VGS confirms it under the same probe.

## Not governed

What a plugin may declare and open, which is [commands-are-data.md](commands-are-data.md); the root steps a TUI runs, which is [system-steps.md](system-steps.md).
