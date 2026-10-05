# Capture

Capture takes PNG screenshots. It can save them, copy them, or do both. It also records the screen on Arch and copies English text from a selected area.

![Capture widget](../../../docs/images/plugins/vgs.capture-widget.webp)
![Capture options](../../../docs/images/plugins/vgs.capture-panel.webp)

Images come from `scripts/readme-shots.sh` in the nested sandbox.

## Features

- Screenshot of the focused output.
- Area screenshot over a still screen. A click selects the window or display under the pointer.
- Selection of a window or display, or one image of all displays.
- Screenshot delay with a countdown in the bar. The same key or a click on the countdown cancels.
- Choice of save and copy, copy only, or save only. The pointer is optional.
- Screen recording with desktop audio, microphone audio, both or neither.
- Text recognition from a selected area.
- Capture options and a recording indicator in the bar.

## How it works

Click Capture to open its options. A screenshot uses the selected result choice. A notice names a saved file or confirms a copy. Selection holds the screen still and shades it while you choose a box. Escape or the same key cancels selection. A delayed screenshot releases the still screen after selection and captures new content when the countdown ends. Recording also offers each output as a box. Click the recording indicator, or press its shortcut again, to stop and save. A missing tool opens the install notice for the action that needs it.

## Settings

Set the screenshot result, click selection, delay, pointer, time limit, folders and recording audio in the Capture panel or Settings. Empty folder fields use Screenshots in your XDG Pictures folder and Screencasts in your XDG Videos folder. Custom folders use an absolute path or start with `~/`. The Keys row in Settings changes each shortcut.

Recording needs `gpu-screen-recorder` on Arch. Fedora shows recording as unavailable when that tool is absent. Text recognition uses English data. When Tesseract is absent, the Arch install notice installs `tesseract-data-eng`, which also installs Tesseract. If Tesseract is present but cannot read its English data, Capture shows that error and keeps the clipboard. The current install notice cannot repair missing data for a tool that is present.

## IPC

These optional commands address the service on a running VGS session.

| Action | Command | Shortcut name | Default key |
|---|---|---|---|
| Focused-output screenshot | `vgshell ipc call vgs.capture invoke screenshot ''` | `vgs.capture:screenshot` | Print |
| Area screenshot | `vgshell ipc call vgs.capture invoke screenshot-area ''` | `vgs.capture:screenshot-area` | Super+Shift+S |
| Window screenshot | `vgshell ipc call vgs.capture invoke screenshot-window ''` | `vgs.capture:screenshot-window` | None |
| Selected-display screenshot | `vgshell ipc call vgs.capture invoke screenshot-display ''` | `vgs.capture:screenshot-display` | None |
| All-display screenshot | `vgshell ipc call vgs.capture invoke screenshot-all ''` | `vgs.capture:screenshot-all` | None |
| Start or stop recording | `vgshell ipc call vgs.capture invoke record ''` | `vgs.capture:record` | Super+Shift+R |
| Copy text | `vgshell ipc call vgs.capture invoke text ''` | `vgs.capture:text` | Super+Ctrl+Print |
| Open or close options | `vgshell ipc call vgs.capture invoke toggle ''` | `vgs.capture:toggle` | Super+Ctrl+Shift+S |
