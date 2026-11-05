# Capture developer reference

Read when changing capture actions or their worker protocol. The [manifest](manifest.json) owns shortcut defaults, settings, requirements and entry points. [Service.qml](Service.qml) registers the actions as shortcuts and IPC handlers and owns their jobs.

## Action lifecycle

The service's `invoke`, `launch`, `accept` and `finished` functions connect action admission, selection, worker events and completion. The worker is [helper/capture.py](helper/capture.py). [ShareSession.qml](ShareSession.qml) owns the portal sharing integration. Change the relevant owner instead of running another capture from a view.

Selection and file completion are different phases. Cancellation remains possible until the screenshot file is written. A delayed screenshot releases the frozen selection image before the countdown captures new content. Recording finalization can continue while another capture starts.

The worker keeps the original recording when audio cleanup or trim and level processing fails. Device enumeration does not open a camera or audio source; an enabled but disconnected camera prevents recording from starting. OCR failure preserves the clipboard. The helper owns the processing parameters and error protocol.

## IPC

An action's IPC name matches its registered shortcut name. Use the service's action declarations for the current set; the manifest owns which ones have default keys.

<details>
<summary>Show command</summary>

```text
vgshell ipc call vgs.capture invoke screenshot-area ''
```

</details>
