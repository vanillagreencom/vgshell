# D076: One-time migrations run once per user, in order, before the shell starts

[← Decision Index](INDEX.md)

**Date**: 2026-09-30
**Status**: Active
**Research**: [VGS-683](https://linear.app/vanillagreen/issue/VGS-683)
**Refines**: [D053](D053-runner-holds-the-instance-lock.md), [D069](D069-runner-supervises-the-shell.md)

**Decision**: One core runner, `bin/vgshell-migrate`, runs each script under `bin/migrations/` once per user in name order, marks success, stops at the first failure and retries it next time. `vgshell run` runs them after taking the instance lock and before starting the shell, and starts the shell whatever they answer; `vgshell self update` runs the updated tree's migrations before its restart.

**Why**: `vgshell run` is the only path every install method reaches, at login, after a package update and after a self-update, so a package hook or a systemd unit would miss installs. A broken migration must never leave the user without a bar. `scripts/test-vgshell-migrate.sh` holds the runner.

**Rejected**: Running migrations only from `vgshell self update`. A package install never calls it.

**Revisit when**: VGS ships a systemd user unit or a package hook that could run migrations earlier, or a migration needs a privilege or a question.
