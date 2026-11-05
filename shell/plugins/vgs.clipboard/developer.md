# Clipboard developer reference

Read when changing capture, history storage or key dispatch. [Service.qml](Service.qml) owns the history and IPC handlers. [ClipboardHistory.js](ClipboardHistory.js) owns entry validation, retention, row filtering and chord selection. The [manifest](manifest.json) owns shortcuts and entry points.

## Capture and dispatch

The [clipboard helper](helper/clipboard.py) owns clipboard I/O, stored files, permissions and capture limits. The [secrets contract](../../../docs/architecture/secrets.md) governs secret hints and copied-data isolation. Keep the limits with their implementing code rather than copying them into a view.

Recorded type and live paste type have different meanings. A copy offering both text and an image is recorded as text. A terminal paste reads the currently offered MIME types, with an image taking precedence, so an unrecorded copy cannot reuse a history entry's type.

The service asks the core to identify the keyboard target before selecting a chord. An unresolved application receives no key. Pasting a history entry still leaves that entry on the clipboard and explains why the key was not sent. `ClipboardHistory.chord` defines terminal, application and VGS-surface handling, including the terminal cut case.

Application identification belongs to the core. A wrapper whose executable is identified only by its desktop entry's `TryExec` remains unresolved; the plugin has no separate desktop-entry resolver.

## IPC

The service header defines handler arguments and replies. Entry actions take an entry ID; `rows` takes a filter and returns the image directory, total count and filtered rows. Clear retains pinned entries.

<details>
<summary>Show command</summary>

```text
vgshell ipc call vgs.clipboard invoke rows 'png'
```

</details>
