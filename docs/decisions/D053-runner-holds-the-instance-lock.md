# D053: The runner holds the instance lock and waits on the shell as its child

[← Decision Index](INDEX.md)

**Date**: 2026-09-29
**Status**: Active (restart's stop → [D069](D069-runner-supervises-the-shell.md))
**Research**: [VGS-609](https://linear.app/vanillagreen/issue/VGS-609)

**Decision**: `vgshell run` keeps the instance lock, starts the shell as a child through `setpriv --pdeathsig TERM`, waits on it and exits with its status. The lock file names the shell's pid, and no process the shell starts holds the lock.

**Why**: A lock descriptor the shell inherits is held by every child the shell starts: a long download kept the lock after the shell died, and `vgshell restart` refused for ten seconds. The parent-death signal keeps one shell per session when the runner itself is killed. `scripts/test-vgshell-run.sh` holds the lock rule.

**Rejected**: A close-on-exec lock the shell takes again. Quickshell gives QML no `flock`, and the gap between exec and the new hold lets a second `vgshell run` start.

**Revisit when**: Quickshell gives QML a file lock, or util-linux drops `setpriv --pdeathsig`.
