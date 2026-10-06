# A budget is twice the highest reading of a named run

Read before touching a latency, a resident-size ceiling or a shader ceiling the smoke reads, or its budget.

## The approach

Every latency, the resident size and every shader cost the smoke reads has a ceiling set at twice the highest reading over a named run on a named machine and date, read at a stated poll interval, printed with the CPU pressure of the run. A reading over its ceiling fails at any pressure. The record lives beside the ceiling: the header of `scripts/qml-smoke.sh` for the first bar, the reconcile, the emoji readers and the resident size; the row's header for the relaunch, lock, TUI and theme readings; `scripts/shader/ceilings.json` for the shader costs. A costly control must exceed the ceiling in every pass.

## Why

A ceiling without its measurement cannot be judged when it fails, and a measurement without its pressure cannot be compared with another run. Twice the highest reading leaves room for load without hiding a regression. Reading the load average would count running and uninterruptible tasks, so the record reads pressure stall information instead. Qt truncates CPU readings to whole milliseconds, so a zero ceiling proves nothing.

## Rules

- Do set a ceiling at twice the highest reading of a named run on a named machine and date, and print each reading with `cpu_some_pct` from `/proc/pressure/cpu`.
- Do print each reading's poll interval beside it: 10 ms for the first bar, one IPC round trip for the build records and the emoji readers, 50 ms for the relaunch and the lock.
- Do read a shell's resident size through `shell_memory_note` before `stop_shell`'s TERM, so a replaced shell is counted; `scripts/smoke/diagnostics.sh` fails a run whose started shell was never read.
- Do wait for a TUI run's end through `expect_run_end`, which fails an idle read past `run_end_ceiling_ms`; the TUI row holds the controls.
- Never add a measurement that moves a panel's row objects through IPC on each poll; count in the probe and return the count.
- Do calibrate a shader ceiling with `scripts/measure-shader.sh --calibrate scripts/shader/ceilings.json --runs N`, require every scene at every scale to match the record's backend and device, and never substitute a presentation interval for a missing GPU timestamp. `scripts/test-measure-shader.py` pins each; a software device exits 77.
- Do take a shader reading as the nearest-rank 90th percentile of its samples after warmup, because a busy host delays a few frames; `scripts/shader/readings.py` holds the rule.

## The canonical example

The header of `scripts/smoke/rows/supervise.sh`: the ceiling, the readings, the run, the machine, the date and the load, in one block above the row. Copy it for a new reading.

## Revisit when

The reference machine changes, or a ceiling fails under a load the record never saw; then measure again and record the new run.

## Not governed

Where the sandbox's faults are excused, which is [validation-smoke-faults.md](validation-smoke-faults.md); the selection of rows, which is [validation.md](validation.md).
