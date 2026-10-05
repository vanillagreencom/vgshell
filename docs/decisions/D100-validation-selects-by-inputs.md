# D100: A change runs the checks its files reach

[← Decision Index](INDEX.md)

**Date**: 2026-10-03

**Status**: Active

**Research**: VGS-786; owner notes 1791061742, 1791061750, 1791061990 and 1791062024; owner answer 1791074117; owner notes 1791161551 and 1791162090 for the lane and batch rules

**Context**: [D008](D008-validation-row-per-change.md) requires a validation row with every change and names no rule for which rows a change runs. `scripts/validate` selects its own rows by input globs, but holds the nested smoke as one row whose inputs include `shell/*`, `bin/*`, `config/*`, `themes/*` and `scripts/smoke/*`. Almost every product change selects it, and it then runs all 72 row files in one session. On host cachy on 2026-10-03, on `main` at `b24fc37b0`, untraced and inside the GPU fence, one run each: `scripts/qml-smoke.sh` took 1,755 s, `scripts/validate offline --full` took 2,024 s over 214 rows and `scripts/validate unit --full` took 1,383 s. The times are the `validate: selected=N area=A secs=S` line of each run and the smoke's own wall time. An audit of the 943 checks in those runs found 7 to delete and 9 to merge, which together save 23 s. The time is in checks that guard real failures, so the saving comes from selection.

**Decision**: D008's rules stay, and selection joins them.

- **A row with every change.** A change that adds a surface, a service or a plugin adds its row under `scripts/smoke/rows/`; a change that adds a check adds its row to `scripts/validate` with its control. The nested sandbox is the only place a validation run starts the shell.
- **Equal inputs, equal checks.** A row no changed file reaches does not run. A diff-scoped `scripts/validate` run selects each row by the input globs the row declares.
- **A smoke row declares its inputs in its own file.** Each file under `scripts/smoke/rows/` carries one input line of globs. `scripts/validate`, which already selects by globs, reads that line. No second runner, cache, schema or tool reads it.
- **A declaration that cannot select runs the row.** A row file with no input line, an unreadable one, or a glob that matches no tracked file runs on every change that selects the smoke. This never fails or blocks a run.
- **The core rows always run.** A run that selects the smoke runs the bar, Hyprland consent, session, start order and authentication sentinel rows whatever the diff holds, and the rows their lines name. The consent row answers the dialog the first shell raises, and the sentinel's reading covers every row the run held.
- **A row that reads another row brings it.** A row whose input line names another row's file reads that row's functions or state, so a run that selects it selects that row too.
- **A harness change runs every row.** `scripts/smoke/harness.sh` carries its own input line naming the harness's own machinery: its libraries, the probe, the helpers it builds and the fixtures every run starts with. A product file the harness copies or edits goes on the line of each row that runs one of its commands itself, edits it, stands in for it or reads its output; the harness's own `vgsh run`, `pid` and `ipc call`, and the `hypr state` and `theme follow` every shell start runs, go on no row's line, since the core rows make them on every run that selects the smoke. A change to `harness.sh`, or a file its input line names, reaches every row, and so does a change to `scripts/qml-smoke.sh`, which holds the latency budgets. The row order lives in `scripts/smoke/rows.list`, whose change reaches only the rows on its added lines and the rows that read a row it unlists. A harness with no usable input line runs every row. A lane runs less in that case: the lane rule below.
- **The full set runs without selection.** `scripts/validate --full`, an unreadable diff, an unknown input that selects the full area, a direct `scripts/qml-smoke.sh` run with no `--rows`, and the release check, which is `scripts/validate all --full`, run every row.
- **The smoke input self-check reports and never fails.** It names each row file with no input line, each declared glob that matches no tracked file, and each function or variable a row takes from another row whose file its line does not name, and its message is the one line to add or fix.
- **A lane runs what its change names.** A lane validates its final diff once: the fast areas `scripts/validate` selects, and of the nested smoke the rows its change names, the rows it edited and the rows whose input line names a file it changed, with the rows those read. That is the selection `scripts/validate qml --changed <base>` prints as `smoke-rows=some`, less the rows selected only because they read the lane's rows. On `smoke-rows=all` because a harness input changed, the lane runs `scripts/qml-smoke.sh --rows` with those rows.
- **A batch run of main covers the rest.** `scripts/main-run.sh unit qml` runs the full unit and qml areas on a detached worktree of main after 5 landings, or 60 minutes after the last batch run with at least one landing since; the local nightly run is the same runner with the `qml` area, which [`.github/workflows/nightly.yml`](../architecture/validation-nightly.md) cannot run. A red run writes its result, names the landings since the last green run and exits non-zero. It opens nothing and gates nothing: the overseer files one fix item, which goes ahead of other work. No lane waits for a batch run.
- **A lane lands without an order when no other landing lane shares its files.** It rebases onto main and pushes; a clean rebase needs no new run, and a rebase with conflicts runs the lane's named rows again. Lanes that share a file land in the order the overseer gives.
- **Wall time is read, not capped.** A run's wall time is the `secs=` value of the `validate: selected=N area=A secs=S` line it prints, and the `validate: secs=<seconds> exit=<status> row=<label>` lines name the rows that took it. Recurring delays are reviewed and demonstrated waste is fixed; inputs are never narrowed and suites never split to meet a number.
- **A figure names its measurement.** Every budget a script or document states was measured by that script on the machine and date it names.
- **A slow check is never deleted for being slow.** A check that guards a real failure is split or selected by its inputs. A deletion names why no real failure is lost.

**Rationale**:

- Per-change checks catch a regression in the change that made it, and a sandbox whose verdict depends on the machine it ran on is not a sandbox. Both reasons are D008's and still hold.
- A 29-minute smoke on almost every change makes each fix round cost as much as a full run, so lanes wait on checks no changed file reaches.
- One input line beside the row keeps the declaration where the row's author edits, and one reader keeps one answer to which rows run.
- A missing declaration that ran nothing would lose coverage without a sign. Running the row costs time and loses nothing.
- Wall time read from a line every run already prints needs no new instrument.
- A lane that runs every unit and smoke row pays for checks no changed file reaches. One batch run after several landings catches what the narrower lane run misses, a few landings after the change that caused it.

## Alternatives Considered

| Alternative | Why rejected |
|---|---|
| Delete or merge checks to shorten the run | The audit's 7 deletions and 9 merges save 23 s of the 5,162 s the three measured runs total. |
| A table of row inputs in `scripts/validate` | A row file added without a table entry has no declaration to find beside it, and two files change for one row. |
| A smoke input self-check that fails on a missing declaration | It blocks an agent on bookkeeping. The row still runs, so no coverage is at risk. |
| A nightly or batch full run in place of per-change selection | A regression would show only after later landings, with each of them a suspect. The batch run adds to selection and replaces none of it. |
| A monitor-size matrix for the smoke | `hidpi.sh`, `displays.sh`, `monitors.sh` and `monitor-outputs.sh` are the multi-size coverage. A size joins them only when a real failure escapes the current rows. |

## Omarchy comparison

Checked against basecamp/omarchy `quattro` at `5c4da0214`: `docs/testing.md` and `test/`.

| Omarchy | VGS | Where VGS takes it, or why it differs |
|---|---|---|
| `./test/all` runs `./test/cli` and every `test/shell.d/*-test.sh` on every run. It selects nothing by the diff. | `scripts/validate` selects rows by input globs. | Differs: Omarchy's two suites start no compositor per file. VGS's smoke starts a nested Hyprland and shell and takes 1,755 s, so running all of it on every change is the cost this record removes. |
| A new test is one file dropped into `test/shell.d/`; the runner finds it by name. | A new smoke row is one file under `scripts/smoke/rows/` with its input line inside it. | Taken: the row's file is the only place its author edits. |
| The graphical acceptance suite is outside `./test/all` and runs in a disposable VM. | The nested smoke is a `scripts/validate` row. | Differs: VGS has no VM host, and the nested sandbox is its only shell start. |

**Revisit When**: CI gains a Wayland-capable runner; a check needs host state the sandbox cannot reproduce; or a regression lands that a row the diff did not select would have caught.

**Verification**: Wall time is read from the `validate: selected=N area=A secs=S` line of each run. `scripts/test-validate.sh` holds the controls of row selection in `scripts/validate`, and one must-fail control for each smoke row selection rule [validation-runner.md § Method](../architecture/validation-runner.md#method) lists under Controls. `scripts/test-main-run.sh` holds the controls of the batch runner's verdict and landing count.

**References**: [D008](D008-validation-row-per-change.md), [D099](D099-no-amdgpu-node-in-validation-runs.md), [validation-runner.md](../architecture/validation-runner.md), [validation-smoke.md](../architecture/validation-smoke.md)
