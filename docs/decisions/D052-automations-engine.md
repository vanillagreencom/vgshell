# D052: Automations run under systemd user timers, compiled and guarded by one judge

[← Decision Index](INDEX.md)

**Date**: 2026-09-29
**Status**: Active
**Research**: [VGS-600](https://linear.app/vanillagreen/issue/VGS-600)
**Refines**: [D033](D033-floating-tuis-are-core.md), [D035](D035-manifest-requirements.md), [D037](D037-plugin-status.md)

**Decision**: Each automation is a systemd user timer and service pair, or a crontab line where no user manager answers, compiled and guarded by one judge, run from an engine copy outside the plugin snapshot, and notifying through freedesktop hints that carry a path, never a command.

**Why**: A run must happen with the shell down, so the schedule belongs to the user's service manager. One judge for calendar, guard and preview keeps the preview from showing a run the scheduler never makes. `scripts/test-automations-logic.js` compares each calendar with `systemd-analyze calendar`.

**Rejected**: A timer inside the shell, or transient `systemd-run` timers. Nothing runs while the shell is down, and a transient timer vanishes at reboot and cannot carry catch-up.

**Revisit when**: A core notification capability carries clicks, systemd drops user timers or `Persistent=`, or the four frequencies cannot express a needed rule.
