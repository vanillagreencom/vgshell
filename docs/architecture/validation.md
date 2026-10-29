# Validation

Read before changing `scripts/validate`, a row or its verdict, a row's inputs, a test's environment, the nested sandbox or its harness, a fault the smoke excuses, a budget, or a Jarvis test.

## The approach

`scripts/validate` runs the rows a change reaches, once, on the final diff: [D100](../decisions/D100-validation-selects-by-inputs.md). A row whose inputs it cannot read runs.

Every validation row enters one world in `scripts/smoke/gpu-fence.sh`: [D112](../decisions/D112-one-world-owns-the-test-run.md). Package and nix use their own containers; the world's control runs outside the boundary it tests. The world owns the run root, bounds writes and hides the live session. The harness builds its own Hyprland inside it. A Jarvis suite also enters `jarvis_env_run`. The Jarvis self-test declares its account, filtered bus and network exceptions at entry. No process a nested run starts opens an amdgpu node: [D099](../decisions/D099-no-amdgpu-node-in-validation-runs.md).

A check that could not run says so, and that is never a pass: exit 77 in [AGENTS.md](../../AGENTS.md) § Commands. A sandbox fault excuses only a reading the sandbox can spoil. A budget stands beside the run that measured it.

## Why

Only selection cuts the time a fix round costs. A row that runs when it cannot prove it is unaffected keeps the coverage a skipped row would silently lose.

Stand-ins alone cannot bound a run. A missing stand-in can expose a host command, and a cleanup target can name the checkout. The world makes the host read-only, hides session sockets and the network, and gives one owner the run's temporary trees. Authentication stand-ins still refuse privileged steps.

Rows share one sandbox. A row that leaves state changes what a later row reads, so a scoped run and a full run disagree. A wait on time passes on a fast machine and fails on a loaded one. A command that fails outside every check loses every later check in its row, and an unbound variable ends the run with every later row unreported.

A broken environment that reads as a pass hides the regression the check exists to catch. A ceiling without its measurement cannot be judged when it fails, and a reading without its CPU pressure cannot be compared with another run.

## Rules

### Selection

- Do declare every file a row reads, and the file of every row whose functions or state it uses, on its input line in the form [scripts/AGENTS.md](../../scripts/AGENTS.md) gives. An undeclared read skips the row on a change that breaks it. The `smoke rows name the rows they read` row of `validate tools` refuses a function or variable read from an undeclared row; gap: no check finds a product file a row reads but does not declare.
- Never put a product file on the input line of `scripts/smoke/harness.sh`; a change to it runs every row. Review holds it.
- Never add a `repo` row for a check a path pattern can select; a `repo` row runs on every change. Review holds it.
- Never leave a row out of a scoped run without a line that names it. `scripts/test-validate.sh` holds the lines a scoped run prints.

### Plugin inputs

- Do name the plugin files a row loads on its input line, never the plugin's folder. A file the row's shell never builds cannot change the row's reading, and a folder input runs the row for every file in it. The Settings window builds `Window.qml` and the files it names, and builds `StatusLine.qml`, `KeyField.qml` or `RowsList.qml` only for a plugin page whose manifest declares a status entry, a shortcut or a `rows` list, so a row that opens no such page names none of them. `scripts/test-validate.sh` holds the selection over a real row's input line.
- Do name the files of the plugin's entry points that the row reaches itself, such as a service the row calls over IPC or a widget it reads. A started shell loads every always-on entry point for every row, and the core rows cover it.
- Do keep `manifest.json` where the row loads the plugin at all. The core reads it to build each surface.
- Keep the plugin folder where the row reads the plugin as a whole or its loads cannot be read, such as a row that opens pages by a variable it computes: [D100](../decisions/D100-validation-selects-by-inputs.md) runs a row whose inputs it cannot read. Review holds it.
- Gap: no check reads which files a row loads. A manifest that gains a status entry, a shortcut or a list makes every page of that plugin load more files, so the rows that open its page need the new file on their line. Review holds it.

### Test isolation

- Do run every check through the row runner in `scripts/validate`. The world gives each row its own home, XDG directories and scratch root, and removes them after the row. Package and nix use their own containers; `scripts/test-gpu-fence.sh` runs outside the world to test its boundary. Selection and last-pass records stay in validate's own process. `scripts/test-validate.sh` holds it.
- Do keep scratch indexes and their new git objects under the row root. A row reads the checkout's existing objects without writing its git directory. `scripts/test-validate.sh` holds it.
- Do prepare the catalog's pinned archive listings before its offline row enters the world. `scripts/validate` calls `scripts/check-catalog-wallpaper-names.js --prepare`, whose existing downloader verifies each archive's size and SHA256, and keeps only image names at `${XDG_CACHE_HOME:-$HOME/.cache}/vgshell/validate/theme-listings/<archive-sha256>/listing.json`. The row consumes this directory through the world's read-only `--input` bind, including when the directory is under the caller's masked `/tmp`. An absent listing is an input-step failure, never an offline download or exit 77. `scripts/test-check-catalog-wallpaper-names.js`, `scripts/test-validate.sh` and `scripts/test-gpu-fence.sh` hold it.
- Do use `scripts/validate --prepare-catalog-inputs` for the same parent-owned preparation in nightly. `.github/workflows/nightly.yml` restores and saves `/home/ci/.cache/vgshell/validate/theme-listings` with a key containing the hash of `themes/catalog/index.json`; a cache miss runs the producer before offline validation. The former `.git/vgs-catalog-listings` is a rebuildable cache and has no reader or migration in the new code. The overseer retires it after every running lane has rebased past this change.
- Do run every test and sandbox process under the test-run marker `VGS_TEST_RUN=1`. `scripts/test-vgshell-reload.sh` holds the theme judge's refusal under it.
- Do give every process a test spawns an explicit environment, never the caller's whole one. Gap: no check reads a test's spawn calls.
- Do let the world set the run's home, XDG directories, private runtime, temporary directory and test marker, and pass only its declared environment table. Display identifiers and the caller's raw session bus never enter. `scripts/test-gpu-fence.sh` holds the boundary.
- Do verify the inherited world's mounts before keeping its root readable in a child world. A marker alone cannot expose the caller's temporary files or sockets. The child keeps the parent's fixtures read-only and owns its own writable root. `scripts/test-gpu-fence.sh` holds it with a planted marker and socket.
- Do show a test's stand-in files at a fixed system path through bubblewrap read-only overlays of the host directories, with a layer holding any missing mount point and a bind over it, never through a path override in the shipped script: [D107](../decisions/D107-format-change-ships-its-migration.md). The scanner's NetworkManager VPN fixtures instead change the fixed directory tuple in disposable scanner copies; the import test consumes core requirement rows. Review holds it.
- Do hand a runner that starts a compositor, the shell, `qmltestrunner` or a browser to the world before it starts anything. The world binds the host read-only, restores device access, gives `/tmp`, `/dev/shm` and the runtime private tmpfs mounts, masks the caller runtime, `/run/dbus` and `/run/tailscale`, and unshares the network. `scripts/test-gpu-fence.sh` holds it and each entry point's declarations.
- Do declare writable outputs and `--keep` at world entry. An output may not contain the checkout, its git directory or the caller's home. The world alone creates and deletes the run root; a harness closes its recorder and processes. The harness runtime lives under a private runtime child backed by that root so evidence survives namespace teardown. `scripts/test-smoke-owner.sh` holds lifetime and cleanup.
- The owner's home remains readable by absolute path. Redirected HOME keeps tools from selecting it by default; the boundary blocks writes. SIGKILL of the world owner ends its namespace and leaves its root because no cleanup process remains.
- Never let a QML test log a warning it does not declare. `scripts/qml-unit.sh` fails an undeclared log, and its header gives the declaration.
- Never count a mutant as killed on any status but a failed test. `scripts/test-qml-unit.sh` holds it.

### Host safety

- Never authenticate, and never run a real PAM, polkit, sudo, faillock or keyring step; the one exception is the stored key the Jarvis self-test reads under its rules below. The core row `scripts/smoke/rows/auth-sentinel.sh` and `scripts/sandbox-shots.sh` fail a run that reached an authentication stand-in.
- Never let the stand-in terminal run a shipped plugin's TUI script; it runs a fixture copy. `scripts/check-smoke-terminal.py` refuses a row that writes its own, and `scripts/smoke/rows/tui-guard.sh` checks the stand-in at the end of a run.
- Do assert the argv a stand-in recorded, never the effect of the script it stands in for. Review holds it.
- Never add a device fake or a device-command stand-in in a row; `scripts/smoke/devices.sh` owns them. Review holds it.
- Do hide every stand-in registry name from the shell's host PATH in both smoke and capture runs. Removing a stand-in must resolve to `none`. `scripts/test-sandbox-shots.sh` holds it.
- Do start a device row behind the guard in `scripts/smoke/devices.sh`, which records the row not measured when it reads a leak to the host. `scripts/smoke/rows/device-fakes.sh` holds the guard.
- Do capture the sandbox only through `scripts/smoke/shot.sh`, which refuses a socket outside the sandbox's runtime dir and an output outside `tmp/`. `scripts/test-sandbox-shots.sh` holds it.
- Never reach the host compositor from a run: the sandbox reads, dispatches to and draws on no live session. Review holds it.
- Do run every input tool, `wtype`, `$sandbox/click`, `$sandbox/keyboard` and `wl-copy`, only after `nested_input_check` in `scripts/smoke/harness.sh`. It refuses, with no tool call, an environment that does not name the socket the harness started. `scripts/test-smoke-input-guard.sh` holds it for each helper that runs one.
- Never return a secret, or data derived from one, from a sandbox reader; a reader returns state and geometry. Review holds it.
- Never hold the shared sandbox slot gate above its load limit with a lane's own stress load. A proof under load runs once, with the smallest load that reproduces the failure, inside the lane's own slot run, and a Done-when never asks for repeated load runs. Review holds it.

### Nested sandbox

- Do start and stop the sandbox only through `scripts/smoke/harness.sh`. `scripts/test-smoke-teardown.sh` holds the teardown.
- Do draw the nested compositor to the harness's own sink compositor, `scripts/smoke/sink/sink.c`, which the harness starts in the GPU fence before the compositor and stops with it. The sandbox needs no host display or lit monitor and puts no window on the live desktop: the sink configures each output once, at 1920x1080, sends no input, and paces frames at its own 60 Hz. `scripts/test-smoke-sink.sh` holds the sink.
- Do retain a failed or interrupted row's shell instance logs, nested compositor logs, row output and probe dumps after its namespace ends and before the world removes its root. The world is the sole copier, including after a killed runner. `scripts/smoke/evidence.py` owns the retained set: each file's last 1 MiB, at most 8 MiB per row including its index. Copies land in `smoke-evidence-<sandbox>/<row>/` at the output declared on entry: beside the redirected run log, under `tmp/qml-smoke/` for a terminal run, or in `qml-smoke.sh --log-dir`. Passing rows retain nothing. A copy failure reports its cause and preserves the run's verdict. `scripts/test-smoke-evidence.py` holds it.
- Do wait on a state the shell or the compositor reports, never on time. Review holds it.
- Do bound each smoke IPC call at 10 seconds in `scripts/smoke/harness.sh::ipc_call_last`. Expiry kills the call and fails its row as an operation failure, with the target, function and bound. `scripts/test-smoke-dumps.py` holds it, including a reader that catches the failure and a paged reply.
- Never let a reader raise; answer a state word for absent, partial, missing or empty input. `scripts/check-smoke-readers.py` refuses a reader outside `py_reply`, and the harness fails a row on any Python traceback.
- Do name every error line a row provokes in `expected_errors`; the harness fails every other.
- Do let a failed command outside every check end only its row. `smoke_row` in `scripts/smoke/harness.sh` fails the row with the status and runs the next row; a failed restoration ends the run with the original status. `scripts/smoke/rows/updates.sh` holds it. Gap: an unbound variable under `set -u` reaches no ERR trap and still ends the run.
- Do hand the next row the state the row found. The leak check in `scripts/smoke/leaks.sh` fails a row that leaves compositor, harness or stand-in state it does not declare, and `scripts/smoke/rows/leak-check.sh` holds it. Gap: no check compares a plugin's files, its enablement or a key binding before and after a row.
- Do write a disposable QML control in a fresh directory, never in one the shell already read: Qt caches a directory listing, so a control written there fails to load. Review holds it.

The IPC bound prevents a stuck shell from hanging its row. It leaves headroom above the slowest successful call in the selected-row sample, rather than promising a universal latency or linear scaling with host load. [VGS-1831's derivation](https://uploads.linear.app/09589536-0763-447e-a0ed-6d9bf346d4cc/2d2995fe-15f0-497f-a88a-e4a55e92f261/b9ed79ce-32df-47dd-b88c-ed14d46e6124) records the run, population, load, rounding and margin; [VGS-1831](https://linear.app/vanillagreen/issue/VGS-1831/smoke-each-nested-rows-ipc-call-has-a-time-bound-so-a-stuck-shell) holds the raw samples and run log. Its single CPU pressure reading is a point sample, not a description of every call.

### Faults

- Do report a sandbox fault as not measured, and let it excuse only a row that reads geometry or a drawn frame; every other failure is behaviour. The one such fault is a nested output that cannot allocate its buffers; a held mode the output does not take is not measured only when that output logs the rejection during the hold, and fails otherwise. A sink that exits during the start ends it as `missing=sink sink=exited` 77; later it fails the smoke row it ended in, and every runner's teardown prints `sink=exited` with its wait status. `scripts/smoke/verdict.sh` holds the verdict and `scripts/test-smoke-verdict.sh` its controls.
- Never excuse a failure on a held mode that no longer stands; the sink resets no hold. A pointer step whose held mode no longer stands sends nothing and fails its row. `pointer_dispatch` in `scripts/smoke/harness.sh` refuses it through `coordinate_mode_check`, and `scripts/test-mode-hold.sh` holds it.
- Never excuse a run on a log line that names no output; passing runs log it too. `scripts/test-smoke-verdict.sh` holds it.
- Do run a not-measured check again, and report a second sighting. Review holds it.

### Latency budgets

- Do name the tool and the run that produced every figure in a docstring, comment or document. A budget without its measurement is a blocker. Review holds it.
- Do calibrate the actual timed event with its source, engine, fixture, cache and compositor context named; an initial shell start does not establish a later restored shell's distribution. Review holds it.
- Do record beside a ceiling the machine and the CPU pressure its readings ran under. Review holds it.
- Do fail a reading over its ceiling at any CPU pressure, unless the row's header names the CPU pressure, or the 1-minute load average per physical core, above which a reading is not measured; harness.sh's `latency_load_limit` holds the load limit, 1.00. Review holds it.
- Do record a run-end reading past harness.sh's 500 ms `run_end_ceiling_ms` as not measured when the call-to-reading window's CPU pressure is above `latency_pressure_limit` or the 1-minute load per physical core is above `latency_load_limit`, and fail it at or below both. A run that never ends fails at any load, at the harness's poll bound when the host is busy. The controls in `scripts/smoke/rows/tui.sh` hold it.
- Do judge a check of a timed window's frames by the CPU pressure of the window it reads, as its latency is judged: frames that stop short of the notifications row's motion window, or that include none drawn between a settings row pinned-top change's two heights, are not measured above harness.sh's `latency_pressure_limit`, 2.8, and fail at or below it. A captured pinned-top frame that reads no border run fails at any CPU pressure, since pressure can make grim capture fewer frames but cannot blank one. Their controls in `scripts/smoke/rows/notifications.sh` and `scripts/smoke/rows/settings.sh` hold it.
- Do make a budget's control exceed the ceiling on every pass, and floor a shader ceiling at its instrument's logged resolution. `scripts/shader/readings.py` owns the resolution and compares whole instrument ticks so floating-point residue cannot turn equality into an exceedance; `scripts/test-measure-shader.py` holds both.
- Do record a shader's CPU readings above harness.sh's `latency_pressure_limit` as not measured in calibration and check mode. Use the pressure of the on scene that produced each CPU reading. Never excuse a GPU ceiling or a costly GPU control because CPU pressure is high. `scripts/test-measure-shader.py` holds the verdicts.
- Never substitute a presentation interval for a missing GPU timestamp, and never measure a shader on a software device. `scripts/test-measure-shader.py` holds both.

### Jarvis

- Do start a suite's servers, daemon and children inside one `jarvis_env_run` of `scripts/lib/jarvis-env.sh`. `scripts/test-jarvis-env.js` holds each isolation claim its header makes.
- Never pass caller settings, credentials, account roots or live-session identifiers into a suite; a fixture parameter is an argument or a scratch file. `scripts/test-jarvis-env.js` holds the environment scrub; review holds the arguments.
- Never fall back to a host tool for a missing stand-in, and never let a stand-in replace an allow-listed tool. `scripts/test-jarvis-env.js` holds both.
- Never map a scratch or helper failure to exit 77. `scripts/test-jarvis-env.js` holds it.
- Do check every protocol fixture against its schema or sanitized recording. `scripts/fixtures/schema-check.js` holds it.
- Do give a consumer that runs an absolute host executable its own proof: `jarvis_env_run` confines command lookup, not the filesystem. Review holds it.

### Jarvis self-test

`scripts/jarvis-selftest.sh` runs one shipped-daemon voice item in the nested sandbox, outside `jarvis_env_run`, and writes one record. A case may add one follow-up utterance after Always mode opens its follow-up window, and the record then judges that second turn. The Jarvis rules above bind suites; these bind the self-test.

- Never select the self-test from `scripts/validate`; a person or a lane runs it by hand, and `validate` holds only its host-side test. Review holds it.
- Do add a Jarvis voice item's utterance as a case in `scripts/jarvis-selftest-cases/`, run that case once with `scripts/jarvis-selftest.sh --suite <case>`, and report the case record's verdict, first audio and longest gap in `done:`. Recordings of a person's voice are never tracked; the owner's recordings stay on the host and reach a case only through `--voices DIR`. `scripts/test-jarvis-selftest.sh` holds the comparison.
- Do read first audio and the longest silent gap from the speakers' monitor. `scripts/test-jarvis-selftest.sh` holds the measure.
- Never treat the self-test as a room test. Synthetic speech or a recording fed digitally proves the chain, not a microphone, room noise, echo or distance. The time stamps are late by the capture latency, and no budget is enforced.
- Do run the checkout's Jarvis plugin unchanged: no stand-in, scripted port or instrumented copy. `scripts/test-jarvis-selftest.sh` holds it.
- Do hand the sandbox the accounts the run names and no other value of the caller's environment: a sign-in's directory variable, or a saved key's reference, which holds no secret. `scripts/test-jarvis-selftest.sh` holds it.
- Do read a stored key only here, the one keyring step the owner allows any run. The world starts the filtered proxy before namespace entry and mounts only its socket. Its rules pass the declared `org.freedesktop.secrets` reads and deny every other name, unlock and write. The selected sign-in directory has an explicit variable and writable bind; `--net` declares the model's network access. `scripts/test-jarvis-selftest.sh` holds the proxy on a scratch bus.
- Never unlock, store or clear a key, and never let a prompt show. For saved API-key references, a locked keyring ends as `selftest=keyring-locked` and a key that is not stored as `selftest=keyring-no-key`, each exit 77. Copilot reads its native credentials through the same read-only filter and reports its program's named failure when that read cannot authenticate it. Copilot owns its authentication. `scripts/test-jarvis-selftest.sh` holds the reads and the refused unlock.
- Never point a test of the self-test at the caller's keyring; it reads a stand-in secrets service on a scratch bus. Review holds it.
- Do copy the home folder the run names and hand Jarvis the copy; never write the folder itself. `scripts/test-jarvis-selftest.sh` holds the copy and its checksum.
- Do feed a recorded voice only through the voice feed of the sandbox's PipeWire, after the device guard passes and the widget reads the microphone open; a run without the feed ends as `selftest=no-voice-feed`. `scripts/smoke/rows/device-fakes.sh` holds the guard and the feed, and `scripts/test-jarvis-selftest.sh` the refusal.
- Do give the sandbox its own voxtype config for a local voice turn. It points at `VOXTYPE_MODELS` in place, uses the CPU voxtype build, and makes the sandbox voice feed the default source before Jarvis starts. `scripts/test-jarvis-selftest.sh` holds it.
- Never write the caller's voxtype models folder or talk to the caller's voxtype daemon. `scripts/test-jarvis-selftest.sh` holds the models checksum, and review holds the daemon boundary.
- Never mark a record passed unless the turn completed and Jarvis committed a user turn. `scripts/test-jarvis-selftest.sh` holds it.

## The canonical example

`scripts/smoke/rows/supervise.sh`: one input line, its ceiling beside the run that set it, a wait on reported state before each read, and a control for each rule. Copy it for a new row.

## Revisit when

CI gains a runner with a DRM render node, the sandbox gains its own PAM, polkit and session, a check needs host state the sandbox cannot reproduce, the reference machine changes, or a regression lands that an unselected row would have caught.

## Not governed

What a row or a Jarvis suite asserts, which is its own header; the input line format, which is `scripts/AGENTS.md`; the row order, which is `scripts/smoke/rows.list`; the harness's helpers, which are `scripts/smoke/harness.sh`.
