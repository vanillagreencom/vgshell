# D069: The runner supervises the shell

[← Decision Index](INDEX.md)

**Date**: 2026-09-30
**Status**: Active
**Research**: [VGS-679](https://linear.app/vanillagreen/issue/VGS-679)
**Refines**: [D053](D053-runner-holds-the-instance-lock.md)

**Decision**: `vgshell run` relaunches a crashed shell with a backoff of 0.5, 1, 2, 4 and 8 s, gives up after six quick exits in a streak with a Hyprland notice, and never gives up while the session reads as locked. `vgshell restart` stops the runner.

**Why**: Quickshell's own crash handler misses a SIGKILL, a lost Wayland connection and a crash under ten seconds. A stopped runner while locked leaves Hyprland's dead-lock screen that only a TTY clears. `scripts/smoke/rows/supervise.sh` reads the relaunch back.

**Rejected**: A systemd user service with `Restart=on-failure`. VGS ships no unit and starts from Hyprland's autostart, and a unit would be a second owner of the shell's lifetime.

**Revisit when**: Quickshell relaunches after every unclean exit, VGS ships a systemd unit, or a relaunch while locked stops taking the lock over.
