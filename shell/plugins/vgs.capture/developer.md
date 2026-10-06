# Capture developer reference

## Actions

Each action is a shortcut `vgs.capture:<name>` and an IPC function of the same name on a running VGS session. The key column is the manifest's default; a Keys row on the Settings page changes it.

| Name | What it does | Default key |
|---|---|---|
| `screenshot` | Captures the focused output | Print |
| `screenshot-area` | Captures a selected area | Super+Shift+S |
| `screenshot-window` | Captures a window | None |
| `screenshot-display` | Captures a chosen display | None |
| `screenshot-all` | Captures all displays as one image | None |
| `record` | Starts or stops recording an area | Super+Shift+R |
| `record-window` | Starts or stops recording a window | None |
| `record-display` | Starts or stops recording a chosen display | None |
| `record-output` | Starts or stops recording the focused display | None |
| `record-portal` | Starts or stops recording what the screen picker shares | None |
| `text` | Copies text from a selected area | Super+Ctrl+Print |
| `toggle` | Opens or closes the Capture panel | Super+Ctrl+Shift+S |

The IPC form, with the action's name in place of `screenshot-area`:

```text
vgshell ipc call vgs.capture invoke screenshot-area ''
```

## Behaviour

A screenshot uses the selected Screenshot result. A notification names a saved file or confirms a copy. On a saved screenshot, Open shows the image in the image viewer and Edit opens it in the image editor. On a saved recording, Open plays it in the video player. A click on the notification does what Open does. A button shows only when its program is installed, and Dismiss closes the notification. The notifications need the Notifications plugin or another notification service.

Selection holds the screen still and shades it while the user chooses a box. Escape or the same key cancels selection. A delayed screenshot releases the still screen after selection and captures new content when the countdown ends. Recording offers windows and outputs as boxes like an area screenshot, and a box that covers a whole display records that display.

The next capture can start while Capture finishes the saved recording. A recording that failed to start or stopped early shows the end of the recorder's log in a notice. The original file stays when the trim and level step fails.

Capture lists the audio sources and cameras PipeWire offers without opening them. A camera that is switched on but not connected stops the recording before it starts.

Fedora shows recording as unavailable when gpu-screen-recorder is absent. Text recognition reads English unless other languages are chosen. When Tesseract is absent, the Arch install notice installs `tesseract-data-eng`, which also installs Tesseract. When a chosen language's data is missing, the Text languages status offers Install languages in Plugins and in the Capture panel; on Arch and Fedora it installs that data, and on NixOS it names the languages to add to the system configuration. If Tesseract cannot read a chosen language's data, Capture shows that error and keeps the clipboard.
