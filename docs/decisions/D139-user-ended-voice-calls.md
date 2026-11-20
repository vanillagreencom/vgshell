# D139: Ending a Jarvis Voice call retires its brain context

[← Decision Index](INDEX.md)

**Date**: 2026-11-20

**Status**: Active

**Research**: [VGS-2666](https://linear.app/vanillagreen/issue/VGS-2666)

**Supersedes**: [D121](D121-conversation-transport-lifetimes.md) for calls ended by the user.

**Decision**: Close Jarvis retires the call, its exact brain context and its authority. Talk closes that end a call do the same. Stop interrupts current work within the open call. The console keeps earlier messages in History.

**Why**: When a person ends a call and starts another, they expect the next request to start a fresh conversation. A suspended native brain would carry earlier messages and tool context into that request.

**Rejected**: Reusing the previous brain after a deliberate close would require another action to start fresh. Dropping context on every interrupted reply would also discard context the person still needs in the open call.

**Revisit when**: The owner asks to resume a call they explicitly ended.
