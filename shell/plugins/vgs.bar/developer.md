# Bar developer reference

The bar's row in `plugins` in `~/.config/vgshell/shell.json` holds its settings, for example `{ "id": "vgs.bar", "clockFormat": "HH:mm" }`.

`bar.layout` orders plugin IDs and the bar's registered builtin IDs together. `vgs.bar/left-workspaces` and `vgs.bar/center-clock` keep those IDs when moved to another section. Removing an entry hides that builtin.

The bar declares `builtinLabels`, derives `builtinNames` from it and receives `widgetLayout` from the core. Its single keyed model owns Loader delegates under the bar. Each Loader owns a registered `BarWidget` wrapper. The core positions those wrappers through the same section, drag and Hide path as plugin widgets. Hide removes the entry without confirmation or a change to bar settings or enablement. Each builtin has a Show on the bar switch under Settings > Bar. The switch restores its shipped section and declared neighbour order.

`hidden` hides the bar on every screen; its surface is unmapped, so it reserves no space. The launcher's Hide top bar row and the shortcut `vgs.bar:toggle` flip it.

The clock ticks once a minute, or once a second when the format shows seconds.

The bar takes no keyboard focus. Keyboard access to a workspace uses the user's own Hyprland workspace binds.

The bar's service registers the shortcut `vgs.bar:toggle` and the IPC function `toggle` while the bar is the active one. The IPC call is the same toggle as the shortcut:

```text
vgshell ipc call vgs.bar invoke toggle ''
```
