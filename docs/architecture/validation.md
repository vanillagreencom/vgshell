# A change runs the checks its files reach, and no check reaches the person's machine

Read before touching `scripts/validate`, a row or its input line, a test's environment, the nested sandbox or one of its rows, a budget, or a Jarvis test.

## The approach

Every row declares its inputs in its own file, and `scripts/validate` runs the rows a changed file reaches, once, on the final diff, never as a commit, push or merge gate ([D100](../decisions/D100-validation-selects-by-inputs.md)). A declaration that cannot select runs the row.

Every check runs in a private environment and leaves the person's machine as it found it. A row gets a scratch HOME and XDG directories, no global git configuration and `VGS_TEST_RUN=1`. The nested smoke runs in one Hyprland the harness builds from the repository, never in the live session, and a Jarvis suite runs inside one `jarvis_env_run`. No check authenticates against the host, runs a plugin's real TUI script, or reaches a host service a stand-in answers. No process a run starts can open an amdgpu node ([D099](../decisions/D099-no-amdgpu-node-in-validation-runs.md)).

A check that could not run reports not measured, exit 77, and that is never a pass. Every budget a check enforces is tied to a recorded run: the machine, its load and the poll interval sit beside the ceiling in the script, and the readings belong to the issue that set it.

## Why

Only selection cuts the time a fix round costs. A row that runs when it cannot prove it is unaffected keeps coverage that a skipped row would silently lose.

A test that touches the host changes the owner's machine. Namespace isolation does not confine authentication: the sandbox shares the host's PAM, polkit, faillock, files and sudo timestamp. git writes its XDG configuration file wherever one exists, so a scratch HOME alone does not keep a row from editing the developer's git configuration, which may be a dotfiles link. A shipped theme target's reload hook would signal the host's live application from any test tree, so the test-run marker refuses one outside the scratch root. A screenshot through the host socket would capture the owner's desktop.

Rows share one sandbox, so a row that leaves state behind changes what a later row reads, and a wait on time passes on a fast machine and fails on a loaded one. A reader that raises, or a state word that reaches shell arithmetic under `set -u`, ends the run with every later row unreported.

A broken environment that reads as a pass hides the regression the check exists to catch, so a fault excuses only a reading the environment can spoil. A ceiling without its measurement cannot be judged when it fails, and a measurement without its CPU pressure cannot be compared with another run.

## Rules

### Selection

- Do declare a smoke row's inputs on one `# inputs:` line in its leading comment block: the product files it reads, `bin/vgshell` when it runs it, and the file of every row whose functions or state it uses. The `smoke rows name the rows they read` row of `scripts/validate` refuses a line that cannot select.
- Do register a row in `scripts/smoke/rows.list` with its order reason on the comment line above; `scripts/qml-smoke.sh` refuses a malformed line.
- Never put a product file on the harness's own input line, and never name inputs by a wildcard over row files; neither selects a row.
- Do run `scripts/validate --changed <last-validated-commit>` for a fix round and reuse the passing rows whose inputs did not change; never a second full suite. After a restack, the base is the rebased SHA `worktree push` prints.
- Never add a repo row for a check a path pattern can select; a repo row runs on every change.
- Do add a validation row for a new surface, service or plugin in the same change; the `rows_cover_tests` row holds it for test files.

### Test isolation

- Do give every spawned process an explicit environment, and export `VGS_TEST_RUN=1` for every test and sandbox run. `scripts/test-validate.sh` plants a row that writes git's global configuration, and `scripts/test-vgshell-reload.sh` plants a hook outside the scratch root.
- Do declare an expected QML warning with `// expected-log: <message> -- <reason>` directly above the test function; `scripts/qml-unit.sh` fails a log at load or teardown.
- Never count a mutant as killed on any status but a failed test; `scripts/test-qml-unit.sh` pins it.
- Do hand any runner that starts a compositor, the shell, `qmltestrunner` or a browser to `scripts/smoke/gpu-fence.sh`; `scripts/test-gpu-fence.sh` pins the fence and each entry point's call.

### Host safety

- Never authenticate, and never run a real PAM, polkit, sudo, faillock or keyring step. `scripts/smoke/rows/auth-sentinel.sh`, a core row, reads the sentinel log empty, and `scripts/sandbox-shots.sh` fails a run that logged one.
- Never let the stand-in terminal run a plugin's own TUI script; it runs only a byte-identical fixture copy. `scripts/check-smoke-terminal.py` refuses a second writer of the stand-in, and `scripts/smoke/rows/tui-guard.sh` is the guard's control.
- Do read the argv a stand-in recorded, never a script's effect; each plugin's offline suite runs its TUI scripts.
- Never add a device fake or a host-command stand-in in a row; `scripts/smoke/devices.sh` owns them, and `devices_ready`, a device row's first line, records the row not measured when the guard reads a leak. `scripts/smoke/rows/device-fakes.sh` holds the controls.
- Do capture through `scripts/smoke/shot.sh`, which refuses the host socket, the host runtime directory and an output outside `tmp/`; `scripts/test-sandbox-shots.sh` pins it. Never open a host workspace or change host focus from a shots run.
- Never return a password or a matrix from a reader.

### Nested sandbox

- Never start a second shell against the live session or kill Quickshell by name; `scripts/smoke/harness.sh` alone owns the sandbox lifetime. `scripts/test-smoke-teardown.sh` pins the teardown.
- Do wait on a state the shell reports, never on time.
- Never let a reader raise; answer a state word for absent, partial, missing or empty. `scripts/check-smoke-readers.py` refuses a reader that parses its input itself, and the harness fails a row on any Python traceback.
- Do name every error line a row provokes in `expected_errors`; the harness fails every other.
- Do leave shared state as the row found it: a shared fixture neutral outside the row that owns its contract, manifest and configuration restored byte for byte, the nested `hyprland.lua` saved and restored around any key binding, and a System plugin enabled or disabled as before.
- Do write a disposable QML control in a fresh subdirectory, never into `shell/Core`, `shell/Ui` or a plugin directory after startup: Qt caches a directory listing it already read, so a control written there fails to load.

### Faults

- Do report a sandbox fault, such as a mode reset, an unsized output or a failed swapchain, as not measured, and let it excuse only a row that reads geometry or a drawn frame; every other failure is behaviour. `scripts/test-smoke-verdict.sh` pins what each class excuses.
- Never treat exit 77 as a pass; rerun, and report a second sighting.
- Never excuse a run on a log line that names no output; passing runs log it too. `scripts/test-smoke-verdict.sh` pins it.

### Latency budgets

- Do set a ceiling at twice the highest reading of a named run, and record beside it in the script the machine, the date, the poll interval and the CPU pressure read from `/proc/pressure/cpu`; a budget without its record is a defect. Review holds it.
- Do fail a reading over its ceiling at any pressure, unless the row's header states a pressure above which an over-ceiling reading is not measured.
- Do make a costly control exceed the ceiling in every pass, and never set a ceiling of zero: Qt truncates CPU readings to whole milliseconds.
- Do calibrate a shader ceiling with `scripts/measure-shader.sh --calibrate` on the record's backend and device, and never substitute a presentation interval for a missing GPU timestamp; `scripts/test-measure-shader.py` pins each, and a software device exits 77.

### Jarvis

- Do start a suite's servers, daemon and children inside one `jarvis_env_run` of `scripts/lib/jarvis-env.sh`, which isolates processes, the network, command lookup and the session endpoints, but not the filesystem. `scripts/test-jarvis-env.js` pins each isolation claim with a control that breaks it.
- Never pass caller settings, credentials, account roots or live-session identifiers into a suite; fixture parameters enter as arguments or scratch files.
- Never rely on a host fallback for a missing stand-in, and never let a stand-in replace an allow-listed or bootstrap tool.
- Never map a scratch or helper failure to exit 77; `scripts/test-jarvis-env.js` rejects a harness that does.
- Do give every protocol fixture its schema, version or sanitized recording and its date, checked by `scripts/fixtures/schema-check.js`.
- Do give a consumer that runs an absolute host executable its own proof; the boundary is not a filesystem sandbox.

### Nightly run

The one workflow, `.github/workflows/nightly.yml`, runs `scripts/validate --full` for the areas a hosted runner can run, on a schedule while the repository variable `NIGHTLY` is `on`, and reports only. Hyprland allocates buffers only through GBM on a DRM device, so `scripts/main-run.sh qml` runs the `qml` area on a machine that has one.

- Never make a merge read the nightly's result.

## The canonical example

`scripts/smoke/rows/supervise.sh`: one `# inputs:` line, its budget with the readings and the run that set it in the header, a wait on reported state before each read, and a must-fail control per rule. Copy its header for a new row.

## Revisit when

CI gains a Wayland-capable runner, the sandbox gains its own PAM, polkit and session, a check needs host state the sandbox cannot reproduce, the reference machine changes, or a regression lands that an unselected row would have caught.

## Not governed

What each row or Jarvis suite asserts, which is its own header; the order rows run in and the harness's helpers, which are `scripts/smoke/rows.list` and `scripts/smoke/harness.sh`.
