# Web Apps developer reference

Read when changing the app registry, generated entries or browser launch. The [manifest](manifest.json) owns the app setting schema. [Service.qml](Service.qml) owns derived desktop entries and icons; [WebApps.js](WebApps.js) judges registry rows, URLs, window classes and generated entry text.

## Registry and derived files

The Settings app list is the registry. Desktop entries and cached site records derive from it; they are not a second editable registry. [files.sh](files.sh) defines their paths, bounded page and image reads, image checks and removal protocol.

The service serializes saved-record reads, site reads, icon reads and entry writes through one worker. A setting change during a step is reconciled after it ends. Successful site metadata is reused until its address or icon choice changes. Failed reads can retry at the next start or relevant change without looping on one failure.

The service removes derived entries and icons for apps no longer listed. Quickshell's desktop-entry index then exposes those entries to the launcher as installed applications.

## IPC and window identity

The generated entry calls the service's `open` handler with the app's registry name. An open first looks for the Chromium app class corresponding to the URL and reveals that window through the core. With no matching window it resolves the default browser and launches the app.

Window identity uses host and path. Apps with the same host and path therefore share one window even when other URL parts differ. The service's launch deadline suppresses repeated opens while a newly launched window has not mapped.

<details>
<summary>Show command</summary>

```text
vgshell ipc call vgs.webapps invoke open <name>
```

</details>
