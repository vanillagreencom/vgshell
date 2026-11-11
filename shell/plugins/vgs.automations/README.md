# Automations

Automations runs your commands on a schedule. It keeps each run's output and sends an alert when an automation starts failing. It is for anyone who wants a backup, a sync or a script to run on its own.

![The Automations window with scheduled jobs](../../../docs/images/plugins/vgs.automations-window.webp)

## Features

- A window to write, schedule and preview your automations, with the history of every run.
- Schedules from once to every N seconds, minutes, hours, days, weeks, months or years, in local time or UTC. The shortest interval is 10 seconds with the system scheduler, or 1 minute with cron.
- A rest for every N seconds, minutes or hours schedules: Automations skips each scheduled time that comes less than the rest after the last run ended, and Run now never waits for it.
- An end date, or for daily and longer schedules a number of runs.
- Per automation: a shell command, a timeout, a working folder and catch-up of runs missed while the computer was off.
- Run now, and the output of every run.
- An alert on the first failed run, at most one reminder a day while the runs keep failing, and a notification when a run works again.
- A sync job form, opened by Add in Local Sync: choose the From and To folders and rsync or Unison, and Automations writes the command.
- Needs internet, on for a new automation and off for a new sync job, waits for internet access before a run. Turn it off for a local command.
- Runs continue when VGS closes.

## Setup

Automations ships with VGS and is on by default. With the system scheduler, scheduled runs stop when you log out unless you enable them while logged out. Runs scheduled through cron continue after logout.

To enable runs while logged out, select Enable while logged out on the plugin's Setup tab or Run automations while logged out in the launcher. Either opens a floating terminal that asks, then turns it on.

<details><summary>Show command</summary>

```bash
loginctl enable-linger
```

</details>

| Setting | What it changes |
| --- | --- |
| Keep history | How long to keep each run's history and output, from 1 to 30 days. |

[developer.md](developer.md) states how a run works, the files and the plugin's command.
