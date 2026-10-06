# Automations developer reference

[D052](../../../docs/decisions/D052-automations-engine.md) holds the schedule rules, the files and how a run works.

## A run

Saving an automation writes a timer and a service for it under `~/.config/systemd/user/` and enables the timer. The service runs the plugin's runner, never the command directly. Where no systemd user manager answers and `crontab` is on `PATH`, the engine writes a block of the user's crontab instead.

At each run the runner starts the command in the user's login shell and stops it at its timeout. It saves a transcript, each output line with its time, and a record of the outcome under `~/.local/state/vgshell/automations/runs/`.

A failure sends a red notification with the last error lines. With "notify on every run" on, a start and a green finish notification come too. Under the VGS notifications, a click on a finish or failure notification opens the transcript in the user's `$EDITOR`, or with `xdg-open`.

The editor uses presets first, then Custom for every N days, weeks, months or years. Once is stored as a schedule that ends after one run.

Lingering, the systemd setting that keeps the user manager running after logout, is read by the plugin's Settings page. The `linger` TUI asks, then turns it on.

## Definitions

Each automation's definition holds `enabled`, `timeoutSeconds`, `catchUp`, `workingDirectory` and `notifyEveryRun`, defaulting to enabled, 3600 seconds, off, the user's home and off. `AutomationsLogic.js` states every key of a definition and of a schedule. The plugin's one manifest setting is `historyDays`, from 1 to 30 and 30 by default, in its `plugins` row of `~/.config/vgshell/shell.json`.

## The automations command

The plugin's developer command is `bin/automations`. It takes the VGS tree first, `/usr/share/vgshell` for an installed VGS, or a checkout. Its header states every verb, its output and its refusals.

The verbs are `list`, `add`, `edit`, `enable`, `disable`, `remove`, `run-now`, `history`, `clear`, `prune` and `preview`; `list` and `history` take `--json` for a program to read. The service runs `sync`, `scheduler` and `run` itself.

Examples against a checkout:

```text
shell/plugins/vgs.automations/bin/automations --tree "$PWD" add --definition '{"name": "Back up notes", "command": "rsync -a ~/notes /mnt/backup/", "schedule": {"frequency": "weekly", "interval": 1, "weekdays": ["mon", "thu"], "times": ["09:00"], "start": "2026-10-01", "end": {"type": "never"}}}'
shell/plugins/vgs.automations/bin/automations --tree "$PWD" list
shell/plugins/vgs.automations/bin/automations --tree "$PWD" run-now back-up-notes
shell/plugins/vgs.automations/bin/automations --tree "$PWD" history back-up-notes
shell/plugins/vgs.automations/bin/automations --tree "$PWD" preview --schedule '{"frequency": "monthly", "interval": 1, "monthly": {"by": "weekday", "week": 2, "weekday": "tue"}, "times": ["09:00"], "start": "2026-10-01", "end": {"type": "count", "count": 6}}'
```
