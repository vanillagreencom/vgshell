# D087: Coding tasks are controlled through a recorded process group

[← Decision Index](INDEX.md)

**Date**: 2026-10-01
**Status**: Active
**Research**: the Jarvis plan attached to [VGS-623](https://linear.app/vanillagreen/issue/VGS-623)
**Refines**: [D033](D033-floating-tuis-are-core.md), [D072](D072-coding-task-records-and-four-fact-state.md)

**Decision**: A launcher forks the agent as leader of a new process group and records its pid, pgid, sid and start ticks before it execs. The runner verifies that identity before every signal, escalates against the group, and writes `stopped` only after the group reads empty. The launch spec travels as a private file, never as TUI arguments.

**Why**: A pid can be reallocated after the agent ends, and a terminal's tree says nothing reliable about which processes are the task's. A killed leader stays a zombie until reaped, so only the empty read proves a stop finished, and a goal in TUI arguments lands in every process list. `scripts/test-jarvis-task-runner.js` holds the identity check.

**Rejected**: Signalling the terminal's or the tmux pane's process tree. It reaches the shell and the terminal, and gives no identity across a pid reuse.

**Revisit when**: A vendor agent offers a documented stop interface, Linux exposes a pidfd for a whole process group to unprivileged callers, or a task must run outside the user's PID namespace.
