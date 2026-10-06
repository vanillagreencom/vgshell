# D072: Coding-task records keep four independent facts

[← Decision Index](INDEX.md)

**Date**: 2026-09-30
**Status**: Active
**Research**: the Jarvis plan attached to [VGS-623](https://linear.app/vanillagreen/issue/VGS-623)
**Refines**: [D033](D033-floating-tuis-are-core.md), [D052](D052-automations-engine.md)

**Decision**: A task record keeps the process, turn, wait and reported-outcome facts apart. Events are written by rename under one lock, replayed from disk at start, and produced from a content-addressed copy, never a plugin snapshot.

**Why**: A coding agent ends a turn while it waits for permission, and exit 0 says nothing about whether the work succeeded. A snapshot vanishes at restart while a task outlives the shell. `scripts/test-jarvis-tasks.js` holds the record.

**Rejected**: One stored task state. It loses the difference between a finished turn and a reported outcome.

**Revisit when**: A vendor supplies a durable task-record interface, or the process-control owner changes.
