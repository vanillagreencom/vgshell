# Capture

Capture saves screenshots and copies them as PNG images. It also records the screen on Arch and copies English text from a selected area.

![Capture widget](../../../docs/images/plugins/vgs.capture-widget.webp)
![Capture options](../../../docs/images/plugins/vgs.capture-panel.webp)

Images come from `scripts/readme-shots.sh` in the nested sandbox.

## Features

- Screenshot of the focused output.
- Area screenshot over a still screen. Escape or a second press of the key cancels.
- Screen recording with desktop audio, microphone audio, both or neither.
- Text recognition from a selected area.
- Capture options and a recording indicator in the bar.

## How it works

Click Capture to open its options. A screenshot is saved and copied to the clipboard. A notice names the saved file. An area screenshot, a recording and a text capture hold the screen still and shade it while you drag a box. Recording also offers each output as a box. Click the recording indicator, or press its shortcut again, to stop and save. A missing tool opens the install notice for the action that needs it.

## Settings

Set the screenshot folder, recording folder and recording audio in the Capture panel or Settings. Empty folder fields use Screenshots in your XDG Pictures folder and Screencasts in your XDG Videos folder. Custom folders use an absolute path or start with `~/`. The Keys row in Settings changes each shortcut.

Recording needs `gpu-screen-recorder` on Arch. Fedora shows recording as unavailable when that tool is absent. Text recognition uses English data. When Tesseract is absent, the Arch install notice installs `tesseract-data-eng`, which also installs Tesseract. If Tesseract is present but cannot read its English data, Capture shows that error and keeps the clipboard. The current install notice cannot repair missing data for a tool that is present.

## IPC

These optional commands address the service on a running VGS session.

| Action | Command | Shortcut name | Default key |
|---|---|---|---|
| Focused-output screenshot | `vgshell ipc call vgs.capture invoke screenshot ''` | `vgs.capture:screenshot` | Print |
| Area screenshot | `vgshell ipc call vgs.capture invoke screenshot-area ''` | `vgs.capture:screenshot-area` | Super+Shift+S |
| Start or stop recording | `vgshell ipc call vgs.capture invoke record ''` | `vgs.capture:record` | Super+Shift+R |
| Copy text | `vgshell ipc call vgs.capture invoke text ''` | `vgs.capture:text` | Super+Ctrl+Print |
| Open or close options | `vgshell ipc call vgs.capture invoke toggle ''` | `vgs.capture:toggle` | Super+Ctrl+Shift+S |
