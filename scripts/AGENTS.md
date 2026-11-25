# scripts/

Validation and measurement scripts. Runtime helpers belong in `bin/lib/`, never here. The `runtime_reads_no_scripts` check in `scripts/validate` refuses a load from `bin/` or `shell/` into `scripts/`.

## Rules

- Register checks and their must-fail controls in `scripts/validate`. Name a control `test-<subject>` for the script it exercises. `qml-smoke.sh` is a runner and has no separate control; `test-validate.sh` holds controls for checks implemented by `validate`. A new row whose inputs match a case's file in `test-validate.sh` adds its command to that case's expected plan.
- Each script's header owns its command and output contract.
- Before adding or changing a table row's inputs or a command file's loads: [validation.md § Selection](../docs/architecture/validation.md#selection).
- Put smoke rows under `scripts/smoke/rows/`. `scripts/row_loads.py --smoke` reads a row's inputs from what it loads. Declare `# loads: GLOB [GLOB...] -- REASON` only for a load the reading cannot see: in the row's leading comment block under one of the reasons in [validation.md § Selection](../docs/architecture/validation.md#selection), or above the load site with what it loads. A row whose state another row reads names nothing; the reader's directive names the producing row's file. Every directive in `smoke/harness.sh` and the files it sources is an input of every row, so a load only some callers make stays out of them.
- A change that enables or places a plugin in the harness's user file also updates every row assertion that lists the harness world whole, such as a `hidden=` reply, a capability's holders, `expect_widgets` and a build count.
- Only `scripts/smoke/harness.sh` owns the sandbox lifetime; it sources `scripts/smoke/teardown.sh` for teardown.
- A row types into a notice only after `ipc smoke noticeFocused` reads true.
- Keep files needed after a run under the declared `$smoke_log_dir`, never the world's disposable `$repo`.
- Put disposable instance readers in `scripts/smoke/Probe.qml`, never in shipped components.
- Runtime refusal fixtures belong to the rows that assert their refusal. The consuming row or capture scene owns fixture setup; `scripts/smoke/devices.sh` owns device fakes.

## Read when

- Before running validation, release checks, container install checks or README regeneration: [DEVELOPMENT.md § Test](../DEVELOPMENT.md#test), [§ Release](../DEVELOPMENT.md#release), [§ Containers](../DEVELOPMENT.md#containers) or [§ Regenerate](../DEVELOPMENT.md#regenerate). The Release section limits agents to `--dry-run`.
- Before changing check selection, row inputs, restack coverage or pass reuse: [validation.md § Selection](../docs/architecture/validation.md#selection). `scripts/validate --list` prints the selected commands.
- Before starting a compositor, shell, `qmltestrunner` or browser, or changing world-entry declarations: [validation.md § Test isolation](../docs/architecture/validation.md#test-isolation).
- Before changing sandbox prerequisites, exit handling or logs: [validation.md § Nested sandbox](../docs/architecture/validation.md#nested-sandbox) and [runtime.md § Process](../docs/architecture/runtime.md#process).
- Before changing a memory measurement or its sampler: [runtime.md § Memory](../docs/architecture/runtime.md#memory).
- Before building a release tarball: [distribution.md § Release tarball](../docs/architecture/distribution.md#release-tarball).
- Before changing Gallery component or focus readbacks: [design-system.md § Components](../docs/architecture/design-system.md#components).
- Before changing fixture execution or device fakes: [validation.md § Host safety](../docs/architecture/validation.md#host-safety).
