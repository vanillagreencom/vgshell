# Automations developer reference

Read when changing definitions, scheduling or run admission. The [manifest](manifest.json) owns plugin settings and TUI declarations. [AutomationsLogic.js](AutomationsLogic.js) owns definition validation, defaults, schedules and outcome decisions. The header of [bin/automations](bin/automations) defines its verbs, records, paths and refusals.

## Runner ownership

The engine owns the definition store, scheduler units, run locks, transcripts and failure streaks. Scheduler units run a durable copy of the engine and judge rather than a path in the shell's temporary plugin snapshot. A scheduled or manual run can outlive VGS.

Store mutations hold the store lock. The first read converts version 1 definitions under that lock, preserving their fields and setting `requiresNetwork` to false; the current parser accepts only version 2. New definitions take their defaults from `AutomationsLogic`.

## Network admission

`requiresNetwork` is explicit. The engine does not infer it from a command. `networkAdmission` admits such a command only with NetworkManager FULL connectivity. An unavailable reading or elapsed grace does not admit it. A definition that needs no network makes no connectivity call.

The pending marker retains the original due time and the runner's process-start and boot identity. Cancel, Edit, Disable and Remove cancel a waiting attempt before changing its definition; they do not stop an admitted command. Scheduled waits retain the latest-unhandled-occurrence rule. Manual waits end on connectivity or cancellation.

`outcomeOf` defines the narrow resolver skips. A resolver failure is a scheduled network-dependent command that fails by itself within the DNS window and reports a recognized name-resolution error. After a successful newest ended run, it is skipped as `network-dns`, since FULL can be stale just after a resume. After anything else, the runner asks NetworkManager to re-check connectivity, and the failure is skipped as `network-offline` only when that reading is NONE, PORTAL or LIMITED. FULL, UNKNOWN, a refused re-check or an unreadable reading keeps the failure, so one name that fails while the internet works still alerts. A manual run, a timeout or a signal keeps its normal outcome. Use that judge for both history and notification decisions.

## Notifications

`AutomationsLogic.alertDue` decides whether a failed run alerts, with one rule for every automation. A streak's first failure alerts. A later failure alerts only when it ends on a later local calendar day than the streak's last alert, so a job that keeps failing reminds at most once a day. An alert that notify-send could not deliver stays due. Under `notifyEveryRun`, a failure that is not due an alert replaces its start notification with a failure notification of normal urgency, which expires. The first success after a streak sends the recovered notification. The streak file records when the last alert was delivered.

Failure replacement IDs belong to the notification server that issued them. The engine stores the session bus ID and server owner with each ID, so a restart or new login cannot replace an unrelated notification. A recovery replaces the open failure notification only for that server.

## Developer command

The engine takes the VGS tree before its verb. Use an isolated home for commands that change definitions or run work.

<details>
<summary>Show command</summary>

```text
shell/plugins/vgs.automations/bin/automations --tree "$PWD" list --json
shell/plugins/vgs.automations/bin/automations --tree "$PWD" history --json
```

</details>
