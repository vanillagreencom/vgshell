# D036: A time-boxed passwordless sudo grant is an opt-in core TUI

[← Decision Index](INDEX.md)

**Date**: 2026-09-28
**Status**: Active
**Research**: the platform roadmap attached to [VGS-511](https://linear.app/vanillagreen/issue/VGS-511) § 4

**Decision**: The grant is a core feature, `bin/vgshell-sudo-grant`: an owner-installed root half writes a `NOTAFTER` sudoers rule for 1 to 1440 minutes, a transient timer and a boot cleanup remove it, and the user half asks one confirmation in a floating TUI.

**Why**: A system-wide privilege grant has the manager's standing under [D003](D003-everything-is-a-plugin.md), so no plugin may own it. sudo enforces `NOTAFTER` itself, so the grant ends even when the timer does not run. `scripts/test-vgshell-sudo-grant.sh` holds both halves.

**Rejected**: A permanent `NOPASSWD` rule. A forgotten rule stays for good.

**Revisit when**: VGS ships a distribution package that can own the root half, or sudo drops `NOTAFTER` or `-N`.
