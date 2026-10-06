# D043: A TUI run ends by the release of its own lock

[← Decision Index](INDEX.md)

**Date**: 2026-09-29
**Status**: Active
**Research**: [VGS-576](https://linear.app/vanillagreen/issue/VGS-576), [VGS-590](https://linear.app/vanillagreen/issue/VGS-590)
**Refines**: [D033](D033-floating-tuis-are-core.md)

**Decision**: A run's completion signal is the presenter releasing a lock of that run's own, `<stem>@<run>.lock`, which the core waits on with `flock`. The directory listing stays the fast path and the ended record stays the one data shape. A wait whose records a later run removed exits `gone`, and the core logs it only for a run it still awaits.

**Why**: Qt 6.11.2's `FileInfoThread::dirChanged()` can lose a directory-change wake, so the listing can miss the ended record and keep the key busy forever. `flock` has no fair queue, so a wait on the key's lock could lose to the next presenter, which removes the records it needed. `scripts/test-vgshell-tui.sh` holds both.

**Rejected**: A bounded reconcile timer, which polls and still leaves the listing as what must notice the file; and keeping an earlier run's ended record until the shell read it, which the presenter cannot know.

**Revisit when**: Qt fixes the lost wake and VGS confirms it under the same probe, or the presenter stops removing earlier runs' records.
