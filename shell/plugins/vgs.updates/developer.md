# Updates developer reference

Read when changing checks, cached status or update actions. The [manifest](manifest.json) owns settings, entry points, status keys and TUIs. [Service.qml](Service.qml) owns the cached snapshot, check process, cadence and status publication.

## Sources

[bin/check](bin/check) holds the check lock and runs the package, VGS, plugin and theme probes in owned process groups. Its header defines the invocation and signal behavior. It writes the complete normalized snapshot atomically; a failure before publication leaves the last good file.

[NormalizeCheck.js](NormalizeCheck.js) builds the snapshot. [UpdatesLogic.js](UpdatesLogic.js) owns source validation, counts, notes and bounded shared status. A failed source keeps its own error and unknown count. Do not turn it into zero updates or hide it because another source succeeded.

The runner's full package list stays in the status file. Published rows are bounded for views; their omitted count describes what publication left out.

## Cadence

The service waits for cache and boot readings before scheduling. It publishes the cached snapshot, checks when due and accepts an explicit request. Requests during a refresh's startup reads, connectivity admission or check execution join that refresh. An update run asks its own check at its end. The end of its TUI then starts no second check; a TUI whose run asked none starts one. A run's check or TUI end that arrives during a refresh queues one replacement instead, since that refresh may have read the packages before the run's last step. The checking mask stays in place across these phases and any queued replacement, and clears only after the result fields publish successfully. A check process failure retains the snapshot and schedules a retry.

At start and at each TUI end the service reads the pipeline's [outcome file](pipeline.md#outcomes-and-transcript) and publishes it as `lastRun`. The window shows a failed or stopped run's sentence until the next run replaces it.

`UpdatesLogic` owns cache age, prior-boot handling, retry timing, TUI-end detection and the outcome judge. A new service instance does not treat old ended TUIs as new runs.

## IPC

`check` returns `started` when the refresh is accepted after status publication; a check process starts only after startup reads complete and connectivity admission succeeds. It returns `queued` when joining an active refresh. The argument `run` marks the request as an update run's own check, which queues the replacement [§ Cadence](#cadence) describes; any other request schedules no further check. If checking-status publication fails, it returns `refused: check=status-unavailable` and starts no admission or check process. `status` returns the published values. The service's registration block is the current handler list.

<details>
<summary>Show command</summary>

```text
vgshell ipc call vgs.updates invoke check ''
vgshell ipc call vgs.updates invoke check run
vgshell ipc call vgs.updates invoke status ''
```

</details>

## Views and mutations

The widget and window read published status. Refresh calls the service; update actions open the manifest's TUIs. [UpdatesLogic.js](UpdatesLogic.js) owns their display decisions. A check needs no elevation; an update uses the [pipeline contract](pipeline.md).

Reboot-notice actions use the core system step rather than changing host configuration in a view.

## Third-party review

The [package-review contract](../../../docs/architecture/commands-are-data.md#package-review) owns consent, agent selection and admission. [The pipeline reference](pipeline.md#third-party-review) defines how Updates consumes prepared decisions. The plugin owns no separate review agent table, prompt, verdict parser or review TUI.
