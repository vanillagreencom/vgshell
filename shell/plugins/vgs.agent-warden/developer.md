# Agent Warden developer reference

Read when changing status interpretation, setup actions or agent notices. The [manifest](manifest.json) declares entry points, settings and published status. The [README](README.md#how-it-works) defines the observation boundary.

## Status and presentation

[Service.qml](Service.qml) reads the warden's status and publishes the values that the widget, panel and Settings page consume. [WardenLogic.js](WardenLogic.js) judges the input and determines when an unchanged file needs another derivation. [ViewLogic.js](ViewLogic.js) owns state icons, tones, counts, text and summary parsing. Change those owners rather than adding decisions to a view.

The panel's vsys line shows the most serious `warn` or `danger` cause of the summary: the first `danger` cause, else the first `warn` cause. The line draws that cause's `title`, which is vsys's own card title, then the names of its programs, then how many other `danger` causes (problems) and `warn` causes (warnings) vsys found, each count with its noun. VGS writes no words of its own for a cause. The line never draws a process id or a cause's subject, and it draws vsys's text as plain text. When vsys exits 2 after it prints a valid summary, the line still draws. A run that does not start, or a summary the parser refuses, produces one log line and no summary line. The parser refuses a `warn` or `danger` cause that lacks a string `title`, a `processes` list or an `open` list that `shell.tui.run` takes; the log line names the field as `field=verdict[i].<field>`. [Panel.qml](Panel.qml) owns the run and [ViewLogic.js](ViewLogic.js) owns the parser.

Open vsys runs the `vsys` TUI with the shown cause's `open` as its arguments, and with no arguments when `open` is empty or no cause needs attention. [tui/vsys.sh](tui/vsys.sh) hands them to `vsys` and to nothing else. While the vsys window runs with other arguments, a press shows that vsys is already open.

Setup actions use the declared setup TUI, the user timer start or the core's requirement offer. A successful handoff closes the panel. A refusal remains visible and is logged. `ViewLogic.handedOff` and `ViewLogic.refusal` define that distinction.

## Notifications

[Notices.js](Notices.js) owns episode identity, notification modes and delivery choices. An episode sends once when it opens and can send again after evidence clears it. A refusal or failed delivery forgets the episode so the next status tick retries it, including a notice without actions. Dismissal keeps the episode. An unreadable or stale status does not clear an episode it cannot judge.

The service owns the notifier heartbeat. The core delivers notices through `shell.notify.send` with `wait: false`, so a notice without actions releases its core run after delivery while the server keeps the notification. `actions` offers Open vsys as the first action when available and still waits for the user's choice; the callback opens the plugin's `vsys` TUI. Episode memory lasts for that service instance; rebuilding it can notify about an episode still open. Notices use the same tool and worktree names as the panel, without process IDs or scope unit names.

## IPC

`status` returns the published values as one JSON line.

<details>
<summary>Show command</summary>

```text
vgshell ipc call vgs.agent-warden invoke status
```

</details>
