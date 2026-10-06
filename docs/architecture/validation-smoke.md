# The nested smoke is one ordered suite in a sandbox built from the repository

Read before touching the nested sandbox, `scripts/smoke/harness.sh`, a smoke row, a probe reader, a disposable control, or a sandbox screenshot.

## The approach

The smoke runs every row in one nested Hyprland the harness builds from the repository alone, in the order `scripts/smoke/rows.list` fixes, and never touches the live session. A row waits on a state the shell reports, never on time; every reader answers a state word for every state it can meet and never raises; a control for a core file loads as a disposable copy beside the core's own; and a screenshot is evidence only when proven current and taken from the nested socket. No process a run starts can open an amdgpu node ([D099](../decisions/D099-no-amdgpu-node-in-validation-runs.md)).

## Why

Rows share one sandbox, so a row that leaves state behind changes what a later row reads, and a wait on time passes on a fast machine and fails on a loaded one. A reader that raises ends the run with every later row unreported. Qt caches a directory listing, so a control written into a directory the engine already listed fails to load. A stale frame captured as evidence proves nothing, and the host socket would capture the owner's desktop.

## Rules

- Do make a row one file under `scripts/smoke/rows/` and one line in `scripts/smoke/rows.list` with its order reason; `scripts/qml-smoke.sh` refuses other lines.
- Never start a second shell against the live session or kill Quickshell by name; `scripts/smoke/harness.sh` alone owns the sandbox lifetime, and its teardown stops recorded process groups inside the job runner's kill grace. `scripts/test-smoke-teardown.sh` pins the teardown.
- Do start and stop every sandbox shell through `start_shell` and `stop_shell`, address it by `shell_qs_pid`, and wait for `theme_idle` before a `vgshell theme` command; a command sent right after `ping` races the follow that holds the theme lock. The start-order and read-only-prefix rows hold the controls.
- Do route every IPC read through `ipc_via`, every JSON-parsing reader through `py_reply`, and `qs list` through `qs_list`. `scripts/check-smoke-readers.py` refuses a reader that parses stdin itself or lists `qs` raw.
- Never let a reader raise; answer absent, partial, missing or empty. `smoke_row` fails a row on any Python traceback, and `reader_stderr` fails a check.
- Do call `point_item` for a hover and `click_item` for a click; the compositor routes the pointer by where it placed a surface, which trails the layout the probe reads after a resize. The themes row holds the controls.
- Do find a control the way a user reads it, by text, icon name or label, through `scripts/smoke/Probe.qml`, and send keys only once `activeFocusItem` reports the field or page.
- Do write a disposable QML control in a fresh subdirectory whose file basename matches the type, never into `shell/Core`, `shell/Ui` or a plugin directory after startup, and load a core control as a copy beside the core's own through `runnerLoad`, `popupLoad` or `summonLayerLoad`.
- Do name every error line a row provokes in `expected_errors`; `check_unexpected_log` in `scripts/smoke/diagnostics.sh` fails every other.
- Do leave a shared fixture neutral outside the row that owns its contract, restoring manifest and configuration byte for byte, and save, append and restore the nested `hyprland.lua` with `hypr_lua_save` and `hypr_lua_restore` in any row that binds keys.
- Never ship a theme target in the sandbox copy; add fixture targets in the row. Never return a password or a matrix from a reader; the Network and Share readers return masking, length, focus and dimensions only.
- Do capture through `scripts/smoke/shot.sh`, which gives `grim` the nested socket in an empty environment and refuses the host socket, the host runtime directory and an output directory outside `tmp/`; each capture must differ from the shot before it. `scripts/test-sandbox-shots.sh` pins both.
- Do take the held mode again with `hold_restore` before each shot and hover, and never open a host workspace or change host focus from a shots run.
- Do declare `shell_hidden_commands` before sourcing the harness when a run must not see a host tool.

## The canonical example

`scripts/smoke/rows/layers.sh`: one input line, a fixture plugin, every reading through `ipc_via` and `py_reply`, a wait on reported state before each read, and a control per rule. Copy it.

## Revisit when

Quickshell or Hyprland signals the states the rows now read back through the probe, or a hosted runner gains a DRM device.

## Not governed

What a fault excuses, which is [validation-smoke-faults.md](validation-smoke-faults.md); the host guards and device fakes, which is [validation-smoke-host.md](validation-smoke-host.md); the budgets, which is [validation-latency.md](validation-latency.md).
