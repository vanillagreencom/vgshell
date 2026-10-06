# A root change is one row of a closed core table

Read before touching a system step, `bin/vgshell-system`, `vgshell sudo grant`, a udev rule VGS ships, or a plugin that needs a privileged one-time setup.

## The approach

Every privileged one-time setup is one row of the closed table in `bin/vgshell-system`. A plugin names a step in its manifest's `systemSteps`, and the core's floating TUI shows the step's exact commands by path, asks once, writes a root-owned record under `/var/lib/vgshell/system/` before it acts, probes real access rather than a file's presence, and `undo` reverts only what that record names, for the caller's uid, in the boot that made it. The time-boxed sudo grant is a core TUI of the same shape, with an owner-installed root half under `bash -p` and a `NOTAFTER` rule sudo ends itself. On NixOS every root verb writes nothing and prints the configuration snippet instead. The choices are [D081](../decisions/D081-system-steps-closed-core-table.md), [D036](../decisions/D036-time-boxed-passwordless-sudo-grant.md) and [D101](../decisions/D101-greeter-host-and-greeter-system-step.md).

## Why

A plugin must never hold root commands the core did not judge. A rule file's presence proves nothing about access, so a probe that cannot answer reads `unknown`, never `ready`. A user-writable record could steer `undo` into disabling a unit VGS never touched. A device rule grants by `uaccess` alone because a `GROUP` or `MODE` grant reaches SSH and other-seat sessions, and the rule sorts before `73-seat-late.rules`, which applies the tag. The greeter account runs where every password is typed, so the greeter step refuses an install tree root does not own.

## Rules

- Never add a root action outside the table; a manifest's `systemSteps` names table rows only. `scripts/test-vgshell-system.sh` reads `PluginLogic.SYSTEM_STEPS` against the script's table, and `scripts/test-plugin-logic.js` pins the manifest rule.
- Do print every root command by its path and ask one question `VGS_TUI_UNATTENDED` never answers; run only the plan shown. `scripts/test-vgshell-system.sh` and `scripts/test-vgshell-sudo-grant.sh` pin it.
- Do write the record before the commands, so a partial failure is on record, and undo only the recorded change. `scripts/test-vgshell-system.sh` pins both.
- Do probe real access, never a file's presence. `scripts/test-vgshell-system.sh` pins the `unknown` state.
- Never overwrite a destination VGS did not write; refuse a symlink destination and a foreign file as `foreign`. `scripts/test-vgshell-system.sh` pins it.
- Never start greetd from inside a session, enable it only, and refuse the greeter step unless the install tree is root's and writable by no one else. `scripts/test-vgshell-system.sh` pins both.
- Do resolve every command of the root half in the system directories alone, drop the sudo credential before and after each verb, and run the root half under `bash -p` with `PATH`, `LC_ALL` and `SUDO_UID` alone. `scripts/test-vgshell-sudo-grant.sh` pins each under `unshare -r`.
- Do publish a grant by rename only after its expiry timer is armed and the boot cleanup is in place. `scripts/test-vgshell-sudo-grant.sh` pins it.
- Do write nothing and run no sudo on NixOS; print the `security.sudo.extraRules` snippet. `scripts/test-vgshell-sudo-grant.sh` and `scripts/test-vgshell-system.sh` pin the `nixos` state.
- Never let a step reach the host's devices, units or sudo in the sandbox. `scripts/smoke/rows/system-steps.sh` and `scripts/smoke/rows/auth-sentinel.sh` pin it.

## The canonical example

`scripts/smoke/fixtures/plugins/acme.system/`: a plugin that names a step in a status action and nothing else. Copy it; the step itself is a row in `bin/vgshell-system`.

## Revisit when

A step needs a privilege a sudo command cannot give, a distribution ships these grants itself, or VGS ships a package that can own the rule.

## Not governed

The floating terminal the step runs in, which is [tui.md](tui.md); the greeter host's own rules, which are [D101](../decisions/D101-greeter-host-and-greeter-system-step.md) and the `vgs.greeter` README.
