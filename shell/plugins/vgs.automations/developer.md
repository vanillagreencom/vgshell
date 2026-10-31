# Automations developer reference

[D052](../../../docs/decisions/D052-automations-engine.md) holds the schedule rules, the files and how a run works.

## A run

Saving an automation writes a timer and a service for it under `~/.config/systemd/user/` and enables the timer. The service runs the plugin's runner, never the command directly. Where no systemd user manager answers and `crontab` is on `PATH`, the engine writes a block of the user's crontab instead.

At each run the runner starts the command in the user's login shell and stops it at its timeout. It saves a transcript, each output line with its time, and a record of the outcome under `~/.local/state/vgshell/automations/runs/`.

A definition with `requiresNetwork` waits until NetworkManager reports `Connectivity` FULL. The existing runner owns the wait, including Run now and Test run. Neither an unavailable reading nor the end of the active-time grace permits a command to start. Local definitions make no network call. `AutomationsLogic.js` owns the connectivity and missed-run decisions.

The runner retains the original due time in an owned pending marker. The window reads that marker through the engine, shows waiting work and offers Cancel. Edit, Disable and Remove cancel a waiting attempt before changing its definition; they do not stop an admitted command. The engine checks the marker's process start and boot identity, so a crashed runner leaves no live waiting row. Waiting does not require VGS to stay open.

A scheduled wait keeps the existing latest-unhandled-occurrence rule. A late non-catch-up attempt records a neutral skip without a failure alert or streak change. Manual attempts wait until full connectivity or cancellation. The store's first read converts version 1 definitions to version 2 under its lock, preserving their fields and adding `requiresNetwork: false`. Current readers accept only version 2.

NetworkManager's FULL can be stale just after a resume, before names resolve. A scheduled run of a `requiresNetwork` automation whose command exits non-zero by itself within 60 seconds of its start, with a snippet line naming a name-resolution failure (`Could not resolve host: `, `Could not resolve hostname ` or `Temporary failure in name resolution`), is recorded as a `skipped` run with reason `network-dns`, and its unit exits 0, but only when the automation's newest ended run succeeded. A name that never resolves fails from its second run on, every run after. A first run, a run whose history was cleared or pruned, a run after any skip or failure, Run now, Test run, a timeout, a signal and every other failure keep their outcome. `AutomationsLogic.outcomeOf` is the one judge; the history and the list row show a skip's reason.

A failure sends a red notification. Each failure after it replaces that notification and counts the failures since the first one, and the first success after them replaces it with a green recovered notification. The runner keeps the open failure notification's id per automation under `~/.local/state/vgshell/automations/streak/`, with the notification server that gave it: the session bus's id and the unique name owning `org.freedesktop.Notifications`, read with `busctl`. An id names a notification of that one server, so after a shell restart, a new login or a reboot the next notification replaces nothing. With "notify on every run" on, a start and a green finish notification come too, or, for a started command later recorded as skipped, a skipped notification naming the reason, and while runs fail the start replaces the failure notification. Under the VGS notifications, a click on a finish or failure notification opens the transcript in the user's `$EDITOR`, or with `xdg-open`.

The editor uses presets first, then Custom for every N minutes, hours, days, weeks, months or years. Once is stored as a schedule that ends after one run.

Lingering, the systemd setting that keeps the user manager running after logout, is read by the plugin's Settings page. The `linger` TUI asks, then turns it on.

## Definitions

`AutomationsLogic.js` states the definition fields, their defaults and the schedule model. `requiresNetwork` is explicit; the engine never infers it from a command or name. The plugin's manifest setting is `historyDays`, stored in its `plugins` row of `~/.config/vgshell/shell.json`.

## The automations command

The plugin's developer command is `bin/automations`. It takes the VGS tree first, `/usr/share/vgshell` for an installed VGS, or a checkout. Its header states every verb, its output and its refusals.

The verbs are `list`, `add`, `edit`, `enable`, `disable`, `remove`, `cancel`, `run-now`, `history`, `clear`, `prune` and `preview`; `list` and `history` take `--json` for a program to read. The service runs `sync`, `scheduler` and `run` itself.

Examples against a checkout:

```text
shell/plugins/vgs.automations/bin/automations --tree "$PWD" add --definition '{"name": "Back up notes", "command": "rsync -a ~/notes /mnt/backup/", "schedule": {"frequency": "weekly", "interval": 1, "weekdays": ["mon", "thu"], "times": ["09:00"], "start": "2026-10-01", "end": {"type": "never"}}}'
shell/plugins/vgs.automations/bin/automations --tree "$PWD" list
shell/plugins/vgs.automations/bin/automations --tree "$PWD" run-now back-up-notes
shell/plugins/vgs.automations/bin/automations --tree "$PWD" history back-up-notes
shell/plugins/vgs.automations/bin/automations --tree "$PWD" preview --schedule '{"frequency": "monthly", "interval": 1, "monthly": {"by": "weekday", "week": 2, "weekday": "tue"}, "times": ["09:00"], "start": "2026-10-01", "end": {"type": "count", "count": 6}}'
```
