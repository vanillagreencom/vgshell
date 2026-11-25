# D143: A smoke row's inputs are what the row loads

[← Decision Index](INDEX.md)

**Date**: 2026-11-25

**Status**: Active

**Research**: [VGS-2749](https://linear.app/vanillagreen/issue/VGS-2749)

**Supersedes**: [D100](D100-validation-selects-by-inputs.md)'s "every row declares its inputs in its own file", for the nested smoke rows and `scripts/smoke/harness.sh`. D100's selection by reach, [D117](D117-reuse-rows-on-recorded-passes.md)'s pass reuse and the [D137](D137-capability-provider-selection.md) and [D138](D138-qml-module-entry-selection.md) refinements remain.

**Decision**: `scripts/row_loads.py --smoke` reads each nested smoke row's inputs from what its file loads. It follows in-process loads transitively and one process hop. It records a second hop and never reads it. It adds each plugin whose id the row's own files name: the manifest, the entry files the judge accepts, the residue and their QML closure. A row reads a row whose functions or variables it uses, the last earlier definer in run order or every definer when no earlier row defines it, or whose file a `loads:` directive names. A `loads: GLOB... -- REASON` directive covers only a load the reading cannot see, under the reasons `docs/architecture/validation.md` § Selection lists. A load site no directive covers leaves the row untraced, and an untraced row selects the nested smoke on every non-text change. The harness's inputs are its sourced closure and its own directives, never a product file.

**Why**: About 2,000 hand globs on 78 rows drifted from what the rows load. A hand list skips a reached row with no error, and Part A of VGS-2749 found 555 such table misses. On five sampled changes the derived reading dropped no row the hand lines selected and added 0 to 3 rows each. 493 reasoned globs remain of 1,982. Against VGS-2706's hand reading as expected data, one member of 25,489 lies outside the derived reach: a core row's file, which every scoped run holds.

**Rejected**: Following every load transitively, which on the first sample selected 45 rows where the hand lines selected 17, because `bin/vgshell` and the harness reach most of the tree. A plugin kind reaching the host files that name it, and a harness function's loads reaching the rows that call it, which cut the residue from 2,111 to 1,676 (path, row) pairs, added 344 host pairs and need a function partition of every harness library.

**Revisit when**: A reached row is dropped by the derived reading, the residue grows past what review can hold, or the core gains a kind-to-host table the reading could follow.
