# Agent Warden developer reference

Read when changing status interpretation, setup actions or agent notices. The [manifest](manifest.json) declares entry points, settings and published status. The [README](README.md#how-it-works) defines the observation boundary.

## Status and presentation

[Service.qml](Service.qml) reads the warden's status and publishes the values that the widget, panel and Settings page consume. [WardenLogic.js](WardenLogic.js) judges the input and determines when an unchanged file needs another derivation. [ViewLogic.js](ViewLogic.js) owns state icons, tones, counts, text and summary parsing. Change those owners rather than adding decisions to a view.

The panel's vsys summary uses verdict levels alone. It never displays a verdict's subject. A failed run or an unsupported summary produces a log line and no summary line; [Panel.qml](Panel.qml) owns the run and [ViewLogic.js](ViewLogic.js) owns the parser.

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
