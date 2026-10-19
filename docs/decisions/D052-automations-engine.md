# D052: Automations run under systemd user timers, compiled and guarded by one judge

[← Decision Index](INDEX.md)

**Date**: 2026-09-29

**Status**: Active

**Research**: [VGS-600](https://linear.app/vanillagreen/issue/VGS-600), [VGS-1888](https://linear.app/vanillagreen/issue/VGS-1888): every N minutes or hours.

**Refines**: [D033](D033-floating-tuis-are-core.md), [D035](D035-manifest-requirements.md), [D037](D037-plugin-status.md)

**Decision**: Each automation is a systemd user timer and service pair, or a crontab line where no user manager answers, compiled and guarded by one judge, run from an engine copy outside the plugin snapshot, and notifying through freedesktop hints that carry a path, never a command. A rule has one of six frequencies: daily, weekly, monthly or yearly at 1 to 24 times of day, or every N minutes or hours, whose step divides an hour (1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30) or a day (1, 2, 3, 4, 6, 8, 12) and counts from each local midnight. A minutes or hours rule takes no end after N runs.

**Why**: A run must happen with the shell down, so the schedule belongs to the user's service manager. One judge for calendar, guard and preview keeps the preview from showing a run the scheduler never makes. `scripts/test-automations-logic.js` compares each calendar with `systemd-analyze calendar`. systemd's `*:00/N:00` and `00/N:00:00` and cron's `*/N` restart their step at each hour or day, so only a dividing step fires both schedulers and the preview at the same instants. The guard is the same for every frequency: one trigger is one decision on the latest unhandled slot, never one run per missed slot. With a step of 10 minutes or less that slot is always inside the 10-minute late grace, so catch-up decides only whether boot fires a trigger. A count of runs is refused because slots count from midnight of the start date, which a rule saved later that day has passed. An automation keeps its newest 720 ended runs beside the day cutoff, 30 days at 24 a day, so a minutes rule's history stays within a day rule's worst case. The store stays version 1: the new frequencies only widen what a valid record holds ([D107](D107-format-change-ships-its-migration.md)).

**Rejected**: A timer inside the shell, or transient `systemd-run` timers. Nothing runs while the shell is down, and a transient timer vanishes at reboot and cannot carry catch-up. Monotonic timers (`OnUnitActiveSec=`) for intervals: cron has no equivalent, the preview cannot list exact instants, and `Persistent=` does not apply to them. Steps anchored to the start time: cron cannot state them.

**Revisit when**: A core notification capability carries clicks, systemd drops user timers or `Persistent=`, or a needed rule is one the six frequencies cannot express, such as a step that divides neither an hour nor a day.
