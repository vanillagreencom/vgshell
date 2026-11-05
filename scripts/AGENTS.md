# scripts/

Validation and measurement scripts. Runtime helpers belong in `bin/lib/`, never here. The `runtime_reads_no_scripts` check in `scripts/validate` refuses a load from `bin/` or `shell/` into `scripts/`.

## Rules

- Register checks and their must-fail controls in `scripts/validate`. Name a control `test-<subject>` for the script it exercises. `qml-smoke.sh` is a runner and has no separate control; `test-validate.sh` holds controls for checks implemented by `validate`. A new row whose inputs match a case's file in `test-validate.sh` adds its command to that case's expected plan.
- Each script's header owns its command and output contract.
- Put smoke rows under `scripts/smoke/rows/`. Each row declares one `# inputs: GLOB [GLOB...]` line in its leading comment block. Name the files it reads directly, including loads chosen at runtime, and each row whose functions or state it reads. `smoke/harness.sh` declares shared harness inputs in the same form.
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
