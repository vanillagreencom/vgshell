# Agent Warden developer reference

Read when changing status interpretation, setup actions or agent notices. The [manifest](manifest.json) declares entry points, settings and published status. The [README](README.md#how-it-works) defines the observation boundary.

## Status and presentation

[Service.qml](Service.qml) reads the warden's status and publishes the values that the widget, panel and Settings page consume. [WardenLogic.js](WardenLogic.js) reads the input and determines when an unchanged file needs another derivation. [ViewLogic.js](ViewLogic.js) owns state icons, tones, counts, text and summary parsing. Change those owners rather than adding decisions to a view.

vsys judges every state. The status's `items` carry each item's level, words and actions, and the plugin keeps no rule of its own for any of them: an item of a kind it does not know draws by its level, title, detail and actions, as the [warden contract](https://github.com/vanillagreencom/vsys/blob/main/docs/architecture/warden.md#rules) asks. The fresh state is the most serious level among the items and the summary's causes, `calm` for none.

The service runs `vsys --once --summary` once for each status it reads, when vsys comes or goes, and, while the flyout is open and no fresh status comes (not set up or not checking), once as it opens and every 30 s after, since the flyout is the summary's only reader then. It runs one summary at a time, and a run that has not ended after 10 s is stopped and counts as failed. Each `warn` or `danger` cause of the summary is one row in the panel's list, beside the warden's items: vsys's `title`, then the names of its programs, then one action, Show in vsys with the cause's `open` as the vsys TUI's arguments, or Open vsys when `open` is empty. The shield, the panel's sentence and the Settings warden row count the causes with the items. VGS writes no words of its own for a cause. A row never draws a process id or a cause's subject, and it draws vsys's text as plain text. When vsys exits 2 after it prints a valid summary, the rows still draw. A run that does not start, is stopped, or prints a summary the parser refuses drops the causes and produces one log line while its cause stays the same. A run that ends after vsys left the scan keeps no causes. The parser refuses a `warn` or `danger` cause that lacks a string `title`, a `processes` list or an `open` list that `shell.tui.run` takes; the log line names the field as `field=verdict[i].<field>`. [Service.qml](Service.qml) owns the run and [ViewLogic.js](ViewLogic.js) owns the parser.

An item's action runs the `vsys` TUI with the action's `args`. The footer's Open vsys runs it with no arguments. [tui/vsys.sh](tui/vsys.sh) hands them to `vsys` and to nothing else. While the vsys window runs with other arguments, a press shows that vsys is already open.

Setup actions use the declared setup TUI, the user timer start or the core's requirement offer. A successful handoff closes the panel. A refusal remains visible and is logged. `ViewLogic.handedOff` and `ViewLogic.refusal` define that distinction.

## Notifications

[Notices.js](Notices.js) owns episode identity, notification modes and delivery choices. Each item of a fresh status is one episode, keyed by the item's `key`; the plugin's own stale status is one more. An episode sends once when it opens and can send again after evidence clears it. Under the Notifications setting, Problems sends `danger` and `warn` items and Everything adds `info` items. A refusal or failed delivery forgets the episode so the next status tick retries it, including a notice without actions. Dismissal keeps the episode. An unreadable or stale status does not clear an episode it cannot judge.

The service owns the notifier heartbeat. The core delivers notices through `shell.notify.send` with `wait: false`, so a notice without actions releases its core run after delivery while the server keeps the notification. Each notice carries the item's level as its tone, urgency and shield icon, and the item's actions while vsys is installed; a notice with actions still waits for the user's choice, and the callback opens the plugin's `vsys` TUI with the chosen action's `args`. Episode memory lasts for that service instance; rebuilding it can notify about an episode still open. A notice's words are the item's `title` and `detail`, which name no process ID or scope unit.

## IPC

`status` returns the published values as one JSON line.

<details>
<summary>Show command</summary>

```text
vgshell ipc call vgs.agent-warden invoke status
```

</details>
