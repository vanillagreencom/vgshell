# A change runs the checks its files reach, in a private environment

Read before touching `scripts/validate`, a row's input line, a test's environment, a budget, or the QML unit runner.

## The approach

Every row declares its inputs in its own file, and `scripts/validate` runs the rows a changed file reaches, once, on the final diff, never as a commit, push or merge gate ([D100](../decisions/D100-validation-selects-by-inputs.md)). Every row runs in an explicit private environment under `VGS_TEST_RUN=1`: a scratch HOME and XDG directories, no global git configuration, node reached through a link to the resolved binary. A QML unit test fails on any log line it did not declare, and a mutation counts as killed only by a failed test's status. Every performance budget a script states names the machine, the date and the poll interval it was measured with. The nightly workflow runs the areas a hosted runner can run and gates nothing; the `qml` area runs only on a machine with a DRM device.

## Why

A 29-minute smoke on every change cost each fix round a full run while an audit found almost nothing to delete, so only selection cuts the time, and a declaration that cannot select runs the row rather than silently losing coverage. git writes its XDG configuration file wherever one exists, so a scratch HOME alone does not keep a row from editing the developer's own git configuration, which may be a dotfiles link. A shipped theme target's reload hook would signal the host's live application from any test tree, so the test-run marker refuses one outside the scratch root. Hyprland allocates buffers only through GBM on a DRM device, so no hosted runner can run the sandbox.

## Rules

- Do declare a smoke row's inputs on one `# inputs:` line in its leading comment block: the product files it reads, `bin/vgshell` when it runs it, and the file of every row whose functions or state it uses. The `smoke rows name the rows they read` row of `scripts/validate` refuses a line that cannot select.
- Do register a row in `scripts/smoke/rows.list` with its order reason on the comment line above; `scripts/qml-smoke.sh` refuses a malformed line.
- Never put a product file on the harness's own input line, and never name inputs by a wildcard over row files; neither selects a row.
- Do run `scripts/validate --changed <last-validated-commit>` for a fix round and reuse the passing rows whose inputs did not change; never a second full suite. After a restack, the base is the rebased SHA `worktree push` prints.
- Never add a repo row for a check a path pattern can select; a repo row runs on every change.
- Do add a validation row for a new surface, service or plugin in the same change; the `rows_cover_tests` row holds it for test files.

## Test isolation

- Do give every spawned process an explicit environment, and export `VGS_TEST_RUN=1` for every test and sandbox run. `scripts/test-validate.sh` plants a row that writes git's global configuration, and `scripts/test-vgshell-reload.sh` plants a hook outside the scratch root.
- Do name the machine, the date and the poll interval beside every budget in a script; a budget without its measurement is a defect. Review holds it.
- Do declare an expected QML warning with `// expected-log: <message> -- <reason>` directly above the test function; `scripts/qml-unit.sh` fails a log at load or teardown.
- Never count a mutant as killed on any status but a failed test; `scripts/test-qml-unit.sh` pins it.
- Do hand any runner that starts a compositor, the shell, `qmltestrunner` or a browser to `scripts/smoke/gpu-fence.sh` ([D099](../decisions/D099-no-amdgpu-node-in-validation-runs.md)); `scripts/test-gpu-fence.sh` pins the fence, and its exit 77 is never a pass.

## Nightly run

The one workflow, `.github/workflows/nightly.yml`, runs `scripts/validate --full` for the areas a hosted runner can run, on a schedule while the repository variable `NIGHTLY` is `on`, and reports only; `scripts/main-run.sh qml` is the half a hosted runner cannot run.
- Never make a merge read the nightly's result.

## The canonical example

`scripts/smoke/rows/supervise.sh`: one `# inputs:` line, its budget with the readings and the run that set it in the header, and a must-fail control per rule. Copy its header for a new row.

## Revisit when

CI gains a Wayland-capable runner, a check needs host state the sandbox cannot reproduce, or a regression lands that an unselected row would have caught.

## Not governed

The sandbox itself, which is [validation-smoke.md](validation-smoke.md); what a fault excuses, which is [validation-smoke-faults.md](validation-smoke-faults.md); how a budget is set, which is [validation-latency.md](validation-latency.md); the Jarvis test world, which is [validation-jarvis.md](validation-jarvis.md).
