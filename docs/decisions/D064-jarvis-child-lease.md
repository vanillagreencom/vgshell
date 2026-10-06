# D064: Jarvis is one service with a leased child and one wire judge

[← Decision Index](INDEX.md)

**Date**: 2026-09-30
**Status**: Active
**Research**: the Jarvis plan attached to [VGS-623](https://linear.app/vanillagreen/issue/VGS-623)
**Refines**: [D010](D010-facade-scope-not-sandbox.md), [D052](D052-automations-engine.md)

**Decision**: The service owns one Node child whose lease is its closed stdin. One wire judge checks both directions, audio children run under a PID namespace that dies with the daemon, and no systemd unit starts Jarvis.

**Why**: The microphone owner must not outlive the shell or its capture indicator. A pipe closes after a shell crash without relying on QML teardown, where a parent-death signal alone misses a parent already dead when it is installed. `scripts/test-jarvis-daemon.js` holds the lease.

**Rejected**: A graphical-session systemd unit. Its lifetime can exceed the shell's capture indicator.

**Revisit when**: Quickshell provides a stronger child lease, or capture moves to a process the shell cannot own.
