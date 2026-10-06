# A migration changes a user's files once, and never asks

Read before adding a one-time migration or touching `bin/vgshell-migrate`.

## The approach

A migration is a script under `bin/migrations/`, named `<unix time, 10 digits>-<slug>.sh`, run once per user in name order by `bin/vgshell-migrate`, from `vgshell run` before the shell starts and from `vgshell self update` before its restart. It reads the state, changes nothing when there is nothing to change, uses no network, asks no question, takes no privilege and edits nothing under `/etc`. A failure stops the run, shows a notice, and runs again next start; the shell starts whatever it answered. The choice is [D076](../decisions/D076-one-time-migrations.md).

## Why

`vgshell run` is the only path every install method reaches, so a package hook or a unit would miss installs. A broken migration must never leave the user without a bar. `setpriv --no-new-privs` keeps a program a migration starts from gaining a privilege, and the per-migration timeout sits below the time `vgshell restart` waits for the new shell.

## Rules

- Do name a migration by the pattern; a name outside it refuses the whole run. `scripts/test-vgshell-migrate.sh` pins it.
- Do make it idempotent: read the state, change nothing when there is nothing to change. Review holds it.
- Never use the network, ask for a privilege, prompt, or edit `/etc`; the runner gives no new privileges, no stdin and a bounded time. `scripts/test-vgshell-migrate.sh` pins each.
- Do write a setting through `vgshell-plugin-judge seed-setting`, which keeps a symlink a link and leaves a key the user set.
- Never read a secret from a credential store; read presence and unlock nothing. `scripts/test-migration-slack-photos.sh` pins it.
- Do show a failure as a notice that names no command. `scripts/check-user-commands.py` refuses one ([D061](../decisions/D061-no-manual-commands.md)).

## The canonical example

`bin/migrations/1790801764-slack-photos-extra.sh`: a presence read, one seeded setting, nothing when nothing applies. Copy it.

## Revisit when

VGS ships a systemd user unit or a package hook that could run migrations earlier, or a migration needs a privilege or a question.

## Not governed

The runner's own lifetime, which is [runtime.md](runtime.md).
