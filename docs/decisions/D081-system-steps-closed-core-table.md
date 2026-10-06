# D081: Privileged one-time setup is a closed core table of system steps

[← Decision Index](INDEX.md)

**Date**: 2026-09-30
**Status**: Active
**Research**: the System plan attached to [VGS-697](https://linear.app/vanillagreen/issue/VGS-697), [VGS-705](https://linear.app/vanillagreen/issue/VGS-705)
**Refines**: [D036](D036-time-boxed-passwordless-sudo-grant.md), [D061](D061-no-manual-commands.md)

**Decision**: Every privileged one-time setup is one row of a closed table in `bin/vgshell-system`. A plugin names a step in its manifest, and the core's floating TUI runs it after showing the commands. A root-owned record under `/var/lib/vgshell/system/` is written before the commands, and `undo` reverts only what that record names. A device rule grants by `uaccess` alone, never by group.

**Why**: A plugin must never hold root commands the core did not judge. A real-access probe answers what the user needs where a rule file's presence proves nothing, and a user-writable record could steer `undo` into disabling a unit VGS never touched. A group grant reaches SSH and other-seat sessions. `scripts/test-vgshell-system.sh` holds the table.

**Rejected**: `pkexec` per step. D061 elevates inside the floating TUI the commands were shown in, and polkit's agent asks elsewhere.

**Revisit when**: A step needs a privilege a sudo command cannot give, a distribution ships these grants itself, or VGS ships a package that can own the rule.
