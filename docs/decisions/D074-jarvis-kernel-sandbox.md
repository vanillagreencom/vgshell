# D074: Jarvis commands require kernel confinement

[← Decision Index](INDEX.md)

**Date**: 2026-09-30
**Status**: Active
**Research**: the Jarvis plan attached to [VGS-623](https://linear.app/vanillagreen/issue/VGS-623)
**Refines**: [D070](D070-jarvis-action-policy.md)

**Decision**: `Sandbox.js` owns one bubblewrap lifetime. A real kernel probe must pass before the shell adapter offers any tool, there is no unsandboxed fallback, HOME is read-only under the same denied masks Policy uses, and a seccomp filter denies the Unix socket constructors.

**Why**: A command can start another program, and argument classification cannot mediate what that program does. A pathname mask cannot hide an abstract bus socket, so the socket syscalls must go. `scripts/test-jarvis-sandbox.js` runs real bubblewrap in a scratch HOME.

**Rejected**: Shell-token refusal. It cannot confine a program's descendants.

**Revisit when**: A command needs another host mount, endpoint or privilege; the answer is a typed control with a real-kernel test, or a user handoff.
