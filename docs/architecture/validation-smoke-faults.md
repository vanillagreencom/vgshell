# A sandbox fault is not measured, never a pass

Read before touching a sandbox fault the smoke excuses, a mode a row holds on the nested output, or `scripts/smoke/verdict.sh`.

## The approach

A fault of the nested sandbox, a mode reset, an unsized output, a failed swapchain, is reported as not measured and makes the run exit 77. It can excuse only a row that reads geometry or a drawn frame; every other failure is behaviour and is never excused. A row holds a mode through `hold_mode` and `release_mode`, takes it again with `hold_restore` before a read that depends on it, and the hold lives in a file the harness's `hyprland.lua` runs on every load.

## Why

The host sizes the nested window, so a held mode may have no divisor from 2 to 4; the harness trims it, and a trimmed hold differs from the window, so a host configure resets it. A rule set by `hyprctl eval` alone drops on reload. A hidden nested window draws only under the host's `render_unfocused` rule, and nothing nested can substitute. A state word that reaches `$(( ))` under `set -u` ends the run with every later row unreported.

## Rules

- Do run a row that reads positions, sizes or reserved space under `geometry`, one that needs a drawn frame under `render`, and one that reads the hold itself under `hold_check`. `scripts/test-smoke-verdict.sh` pins what each class excuses.
- Do read a count through `read_count`, never a raw reader's word in arithmetic.
- Do hold a mode through `hold_mode` and `release_mode`, and take it again with `hold_restore` before a dependent read. `scripts/test-mode-hold.sh` pins the hold, and the Settings and HiDPI rows hold the controls.
- Never treat exit 77 as a pass; rerun, and report a second sighting.
- Never excuse a run on a bare GBM allocation line; it names no output, and passing runs log it for the headless fallback output. `scripts/smoke/verdict.sh`'s baseline and `scripts/test-smoke-verdict.sh` pin it.

## The canonical example

`scripts/smoke/rows/hidpi.sh`: the hold taken, restored before each dependent read, released at the end, and a `hold_check` row that reads the hold itself. Copy it.

## Revisit when

The nested compositor follows a scale change on a running shell, or the host stops resetting a held mode on configure.

## Not governed

The rows' own assertions and readers, which is [validation-smoke.md](validation-smoke.md).
