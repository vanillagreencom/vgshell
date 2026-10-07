# D072: Coding-task records keep independent facts and a verified process-group identity

[← Decision Index](INDEX.md)

**Date**: 2026-09-30

**Status**: Active

**Research**: the Jarvis plan attached to [VGS-623](https://linear.app/vanillagreen/issue/VGS-623)

**Refines**: [D033](D033-floating-tuis-are-core.md), [D052](D052-automations-engine.md)

**Decision**: A task record keeps the process, turn, wait and reported-outcome facts apart. Events are written by rename under one lock, replayed from disk at start, and produced from a content-addressed copy, never a plugin snapshot. A launcher forks the agent as leader of a new process group and records its pid, pgid, sid and start ticks before it execs. The runner verifies that identity before every signal, escalates against the group, and writes `stopped` only after the group reads empty. The launch spec travels as a private file, never as TUI arguments.

**Why**: A coding agent ends a turn while it waits for permission, and exit 0 says nothing about whether the work succeeded. A snapshot vanishes at restart while a task outlives the shell. A pid can be reused after the agent ends, and a terminal's process tree does not identify the task's processes. A killed leader stays a zombie until reaped, so only an empty group proves a completed stop. A goal in TUI arguments appears in process lists.

**Rejected**: One stored task state, which loses the difference between a finished turn and a reported outcome. Signalling a terminal or tmux pane's process tree reaches the shell and terminal and supplies no identity across pid reuse.

**Revisit when**: A vendor supplies a durable task-record or stop interface, the process-control owner changes, Linux gives unprivileged callers a pidfd for a whole process group, or a task must run outside the user's PID namespace.
