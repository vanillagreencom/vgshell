# D117: A passed row is reused while its recorded inputs are unchanged

[← Decision Index](INDEX.md)

**Date**: 2026-11-02

**Status**: Active

**Research**: [VGS-2186](https://linear.app/vanillagreen/issue/VGS-2186), owner ruling in lane ask 1793671973-2839474-10019.

**Supersedes**: [D100](D100-validation-selects-by-inputs.md)'s rule that every row a change reaches runs; D100's selection still names which rows those are.

**Decision**: `scripts/validate` reuses a reached row that passed on the inputs it has now, as D100's selection names them, instead of running it again. Each row records its pass as it ends, bound to those inputs, so a run cut off at its bound keeps what its ended rows proved. A row whose inputs a record cannot bind always runs, and `--full` reruns every row. The working rule is [validation.md § Selection](../architecture/validation.md#selection).

**Why**: Validate kept a pass only for a whole area, so a run cut off at its bound lost every row it had finished. VGS-2153's run ended 79 of 98 rows before its 7,200 s bound, and the next run would have repeated all of them. A pass on unchanged inputs proves what a rerun would prove.

**Rejected**: A second cache, selector or runner beside validate's selection. Two owners of which rows a change reaches can disagree, and a row one of them reuses would then skip a change the other sees.

**Revisit when**: A reused pass hides a regression that a rerun would have caught, or a row's result depends on state its inputs cannot name.
