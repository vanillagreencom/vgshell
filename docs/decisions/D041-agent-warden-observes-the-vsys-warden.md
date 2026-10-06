# D041: Agent Warden observes the warden vsys ships and never enforces

[← Decision Index](INDEX.md)

**Date**: 2026-09-29
**Status**: Active
**Research**: the platform roadmap attached to [VGS-511](https://linear.app/vanillagreen/issue/VGS-511) § vgs.agent-warden
**Refines**: [D035](D035-manifest-requirements.md), [D037](D037-plugin-status.md)

**Decision**: The warden stays a systemd user timer vsys ships. `vgs.agent-warden` reads its `status.json`, derives a state, publishes it as plugin status, and never enforces.

**Why**: Enforcement has to survive a shell restart or crash, and the plugin manager may not install units or ask for privilege. `scripts/test-agent-warden-logic.js` holds the derivation.

**Rejected**: Porting the corrector into a VGS service. QML has no pidfd or libsystemd path, and correction would stop with the shell.

**Revisit when**: The warden writes a schema major other than 1, or the warden moves into a runtime the shell can host.
