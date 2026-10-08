# D103: The core passwordless sudo grant is timed or indefinite, and its state is read from sudo's own listing

[← Decision Index](INDEX.md)

**Date**: 2026-10-08

**Status**: Active

**Research**: [VGS-1123](https://linear.app/vanillagreen/issue/VGS-1123)

**Supersedes**: [D036](D036-time-boxed-passwordless-sudo-grant.md)

**Decision**: `bin/vgshell-sudo-grant` stays the one owner of the grant and holds two forms. A timed grant is the `NOTAFTER` rule of 1 to 1440 minutes with its expiry timer and boot cleanup. An indefinite grant is one more file, `/etc/sudoers.d/99-vgs-permanent-nopasswd-<uid>`, with no `NOTAFTER` and no timer. Its name is outside the boot cleanup's glob, so it stays across a reboot and ends only when it is turned off. Every grant asks for the duration and a confirmation in a floating TUI, and an indefinite grant asks a second time. The shell reads the grant through `sudo -n -l -l`, which lists the user's rules and never asks or elevates. It reads once when a plugin first holds capability `sudo`, after each grant or revoke run ends, and at a timed grant's deadline.

**Why**: The owner asked for an indefinite option on 2026-10-08, so D036's rejected option is now policy. The grant has the manager's standing under [D003](D003-everything-is-a-plugin.md), so no plugin owns either form. A separate file keeps the timed rule's boot cleanup unchanged. The listing read lets the shell show the grant without a password and without the root half.

**Rejected**: A pacman hook or a quarantine directory that removes the indefinite rule, as Omarchy has. VGS ships no package hook, and the user ends the grant from the bar. A 5 s poll of the grant, as Omarchy's widget runs. One owner reads at the moments the grant can change.

**Revisit when**: VGS ships a distribution package that can own the root half, sudo drops `NOTAFTER`, `-N` or the `Sudoers entry:` lines of `-l -l`, or a forgotten indefinite grant causes harm.
