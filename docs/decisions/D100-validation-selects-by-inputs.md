# D100: A change runs the checks its files reach

[← Decision Index](INDEX.md)

**Date**: 2026-10-03
**Status**: Active
**Research**: [VGS-786](https://linear.app/vanillagreen/issue/VGS-786)

**Decision**: Every change that adds a surface, a service, a plugin or a check adds its validation row in the same change, and the nested sandbox is the only place a shell starts. Every row declares its inputs in its own file, and a diff-scoped run executes only the rows a changed file reaches, with the core rows always on and an undeclarable row always run. A lane validates its final diff once with the rows its change names; a batch run of main covers the rest and gates nothing.

**Why**: A 29-minute smoke on almost every change made each fix round cost a full run, while an audit of the 943 checks found 7 to delete and 9 to merge, saving 23 s of the 5,162 s the three measured runs took on host cachy on 2026-10-03. The time is in checks that guard real failures, so only selection can cut it. A missing declaration that ran nothing would lose coverage silently, so it runs the row instead. `scripts/test-validate.sh` holds the selection.

**Rejected**: Deleting or merging checks to shorten the run, and validation per release, which finds a regression long after the change.

**Revisit when**: CI gains a Wayland-capable runner, a check needs host state the sandbox cannot reproduce, or a regression lands that an unselected row would have caught.
