# Validation

Read before changing `scripts/validate`, a row or its verdict, a row's inputs, a test's environment, the nested sandbox or its harness, a fault the smoke excuses, a budget, or a Jarvis test.

## The approach

`scripts/validate` runs the rows a change reaches, once, on the final diff: [D100](../decisions/D100-validation-selects-by-inputs.md). A row whose inputs it cannot read runs.

Every check runs in a world it owns and leaves the owner's machine as it found it. A row runs in a scratch home under the test-run marker. The nested smoke runs in a Hyprland the harness builds from the repository, never in the live session. A Jarvis suite runs inside `jarvis_env_run`. No process a run starts opens an amdgpu node: [D099](../decisions/D099-no-amdgpu-node-in-validation-runs.md).

A check that could not run says so, and that is never a pass: exit 77 in [AGENTS.md](../../AGENTS.md) § Commands. A sandbox fault excuses only a reading the sandbox can spoil. A budget stands beside the run that measured it.

## Why

Only selection cuts the time a fix round costs. A row that runs when it cannot prove it is unaffected keeps the coverage a skipped row would silently lose.

The sandbox shares the host's files, devices, PAM, polkit, faillock and sudo timestamp. Namespaces do not confine them. A check that reaches one changes the owner's machine, and a capture through the host socket records the owner's desktop.

Rows share one sandbox. A row that leaves state changes what a later row reads, so a scoped run and a full run disagree. A wait on time passes on a fast machine and fails on a loaded one. A reader that raises ends the run with every later row unreported.

A broken environment that reads as a pass hides the regression the check exists to catch. A ceiling without its measurement cannot be judged when it fails, and a reading without its CPU pressure cannot be compared with another run.

## Rules

### Selection

- Do declare every file a row reads, and the file of every row whose functions or state it uses, on its input line in the form [scripts/AGENTS.md](../../scripts/AGENTS.md) gives. An undeclared read skips the row on a change that breaks it. The `smoke rows name the rows they read` row of `validate tools` refuses a function or variable read from an undeclared row; gap: no check finds a product file a row reads but does not declare.
- Never put a product file on the input line of `scripts/smoke/harness.sh`; a change to it runs every row. Review holds it.
- Never add a `repo` row for a check a path pattern can select; a `repo` row runs on every change. Review holds it.
- Never leave a row out of a scoped run without a line that names it. `scripts/test-validate.sh` holds the lines a scoped run prints.

### Test isolation

- Do run every check through the row runner in `scripts/validate`, which gives each row its own home and XDG directories so no row writes the caller's git configuration. `scripts/test-validate.sh` holds it.
- Do run every test and sandbox process under the test-run marker `VGS_TEST_RUN=1`. `scripts/test-vgshell-reload.sh` holds the theme judge's refusal under it.
- Do give every process a test spawns an explicit environment, never the caller's whole one. Gap: no check reads a test's spawn calls.
- Do hand a runner that starts a compositor, the shell, `qmltestrunner` or a browser to `scripts/smoke/gpu-fence.sh` before it starts anything. `scripts/test-gpu-fence.sh` holds the fence and each entry point's call.
- Never let a QML test log a warning it does not declare. `scripts/qml-unit.sh` fails an undeclared log, and its header gives the declaration.
- Never count a mutant as killed on any status but a failed test. `scripts/test-qml-unit.sh` holds it.

### Host safety

- Never authenticate, and never run a real PAM, polkit, sudo, faillock or keyring step. The core row `scripts/smoke/rows/auth-sentinel.sh` and `scripts/sandbox-shots.sh` fail a run that reached an authentication stand-in.
- Never let the stand-in terminal run a shipped plugin's TUI script; it runs a fixture copy. `scripts/check-smoke-terminal.py` refuses a row that writes its own, and `scripts/smoke/rows/tui-guard.sh` checks the stand-in at the end of a run.
- Do assert the argv a stand-in recorded, never the effect of the script it stands in for. Review holds it.
- Never add a device fake or a device-command stand-in in a row; `scripts/smoke/devices.sh` owns them. Review holds it.
- Do start a device row behind the guard in `scripts/smoke/devices.sh`, which records the row not measured when it reads a leak to the host. `scripts/smoke/rows/device-fakes.sh` holds the guard.
- Do capture the sandbox only through `scripts/smoke/shot.sh`, which refuses the host socket and an output outside `tmp/`. `scripts/test-sandbox-shots.sh` holds it.
- Never dispatch to the host compositor, change its focus or open one of its workspaces from a run; read it only. Review holds it.
- Never return a secret, or data derived from one, from a sandbox reader; a reader returns state and geometry. Review holds it.

### Nested sandbox

- Do start and stop the sandbox only through `scripts/smoke/harness.sh`. `scripts/test-smoke-teardown.sh` holds the teardown.
- Do wait on a state the shell or the compositor reports, never on time. Review holds it.
- Never let a reader raise; answer a state word for absent, partial, missing or empty input. `scripts/check-smoke-readers.py` refuses a reader outside `py_reply`, and the harness fails a row on any Python traceback.
- Do name every error line a row provokes in `expected_errors`; the harness fails every other.
- Do hand the next row the state the row found. The leak check in `scripts/smoke/leaks.sh` fails a row that leaves compositor, harness or stand-in state it does not declare, and `scripts/smoke/rows/leak-check.sh` holds it. Gap: no check compares a plugin's files, its enablement or a key binding before and after a row.
- Do write a disposable QML control in a fresh directory, never in one the shell already read: Qt caches a directory listing, so a control written there fails to load. Review holds it.

### Faults

- Do report a sandbox fault as not measured, and let it excuse only a row that reads geometry or a drawn frame; every other failure is behaviour. `scripts/smoke/verdict.sh` holds the verdict and `scripts/test-smoke-verdict.sh` its controls.
- Never excuse a run on a log line that names no output; passing runs log it too. `scripts/test-smoke-verdict.sh` holds it.
- Do run a not-measured check again, and report a second sighting. Review holds it.

### Latency budgets

- Do name the tool and the run that produced every figure in a docstring, comment or document. A budget without its measurement is a blocker. Review holds it.
- Do record beside a ceiling the machine and the CPU pressure its readings ran under. Review holds it.
- Do fail a reading over its ceiling at any CPU pressure, unless the row's header names the pressure above which a reading is not measured. Review holds it.
- Do make a budget's control exceed the ceiling on every pass, and never set a ceiling of zero: Qt reports CPU time in whole milliseconds. Review holds it.
- Never substitute a presentation interval for a missing GPU timestamp, and never measure a shader on a software device. `scripts/test-measure-shader.py` holds both.

### Jarvis

- Do start a suite's servers, daemon and children inside one `jarvis_env_run` of `scripts/lib/jarvis-env.sh`. `scripts/test-jarvis-env.js` holds each isolation claim its header makes.
- Never pass caller settings, credentials, account roots or live-session identifiers into a suite; a fixture parameter is an argument or a scratch file. `scripts/test-jarvis-env.js` holds the environment scrub; review holds the arguments.
- Never fall back to a host tool for a missing stand-in, and never let a stand-in replace an allow-listed tool. `scripts/test-jarvis-env.js` holds both.
- Never map a scratch or helper failure to exit 77. `scripts/test-jarvis-env.js` holds it.
- Do check every protocol fixture against its schema or sanitized recording. `scripts/fixtures/schema-check.js` holds it.
- Do give a consumer that runs an absolute host executable its own proof: `jarvis_env_run` confines command lookup, not the filesystem. Review holds it.

## The canonical example

`scripts/smoke/rows/supervise.sh`: one input line, its ceiling beside the run that set it, a wait on reported state before each read, and a control for each rule. Copy it for a new row.

## Revisit when

CI gains a Wayland-capable runner, the sandbox gains its own PAM, polkit and session, a check needs host state the sandbox cannot reproduce, the reference machine changes, or a regression lands that an unselected row would have caught.

## Not governed

What a row or a Jarvis suite asserts, which is its own header; the input line format, which is `scripts/AGENTS.md`; the row order, which is `scripts/smoke/rows.list`; the harness's helpers, which are `scripts/smoke/harness.sh`.
