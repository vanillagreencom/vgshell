# Automations

Automations runs your commands on a schedule. It keeps each run's output and sends an alert when a run fails. It is for anyone who wants a backup, a sync or a script to run on its own.

![The automations' status on their Settings page](../../../docs/images/plugins/vgs.automations-page.webp)

Screenshot made with `scripts/readme-shots.sh` in the nested sandbox, with the default theme at scale 2.

## Features

- A window with the list of automations, an editor, a preview of the next runs and the history.
- Schedules: once, every day, weekdays, every week, every two weeks, a day of the month, a weekday of the month, a day of the year, or a custom every N days, weeks, months or years.
- An end: never, on a date, or after a number of runs.
- Per automation: paused or enabled, a multi-line shell command, a timeout, a working directory, catch-up of runs missed while the computer was off, and a notification for every start and finish.
- Each command runs in your login shell, so it finds what your terminal finds.
- Run now, a history of every run with its outcome and transcript, and clearing one automation's history or all of it.
- A failed run sends a notification with the last error lines. A click on it opens the transcript.
- A run continues when VGS closes.

## Setup

The plugin ships with VGS and is enabled by default. It schedules runs through systemd. Where no systemd user manager answers, it uses your crontab instead.

Scheduled runs stop when you log out unless systemd keeps your user session running. Enable while logged out, on the plugin's Settings page and in the launcher as Run automations while logged out, opens a floating terminal that asks, then turns that on.

| Setting | What it changes |
| --- | --- |
| Keep history | How long to keep each run's history and output, from 1 to 30 days. |

[developer.md](developer.md) states how a run works, the files and the plugin's command.
