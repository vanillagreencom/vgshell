# Bar developer reference

The bar's row in `plugins` in `~/.config/vgshell/shell.json` holds its settings, for example `{ "id": "vgs.bar", "clockFormat": "HH:mm" }`.

`left`, `center` and `right` list the built-in widgets each section shows, in order, from `workspaces` and `clock`. The defaults are `["workspaces"]`, `["clock"]` and `[]`. An empty list hides them. These lists are not on the Settings page, since the page draws no list.

A name listed twice in one section is drawn once and the repeat is logged. `manager` draws nothing and logs the command that places the Plugins gear, which `vgs.settings` draws.

Plugin widgets follow the built-ins in each section. A plugin's manifest names its section; `bar.layout` in `shell.json` places a widget anywhere. The shipped layout puts the Plugins gear in the right section.

`hidden` hides the bar on every screen; its surface is unmapped, so it reserves no space. The launcher's Hide top bar row and the shortcut `vgs.bar:toggle` flip it.

The clock ticks once a minute, or once a second when the format shows seconds.

The bar takes no keyboard focus. Keyboard access to a workspace uses the user's own Hyprland workspace binds.

The bar's service registers the shortcut `vgs.bar:toggle` and the IPC function `toggle` while the bar is the active one. The IPC call is the same toggle as the shortcut:

```text
vgshell ipc call vgs.bar invoke toggle ''
```
