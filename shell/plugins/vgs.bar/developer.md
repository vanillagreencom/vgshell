# Bar developer reference

The bar's row in `plugins` in `~/.config/vgshell/shell.json` holds its settings, for example `{ "id": "vgs.bar", "clockFormat": "HH:mm" }`.

`bar.layout` orders plugin IDs and the bar's registered builtin IDs together. `vgs.bar/left-workspaces` and `vgs.bar/center-clock` keep those IDs when moved to another section. Removing an entry hides that builtin.

The bar declares `builtinLabels`, derives `builtinNames` from it and receives `widgetLayout` from the core. Its single keyed model owns Loader delegates under the bar. Each Loader owns a registered `BarWidget` wrapper. The core positions those wrappers through the same section, drag and Hide path as plugin widgets. Hide removes the entry without confirmation or a change to bar settings or enablement. Each builtin has a Show on the bar switch under Settings > Bar. The switch restores its shipped section and declared neighbour order.

The bar also declares `builtinFamilies`, `gap` and `separator`. Add gap and Add separator call `shell.builtins.add`, which writes a new entry such as `vgs.bar/gap-3` where a widget dragged to the click would drop, numbered one past the family's highest. Each entry is one builtin with its own registration, so it drags like any widget, and its frame menu's Remove runs the same Hide path, which deletes the entry. A gap is `bar.spacer.gap` wide; a separator is a `divider.thickness` line `bar.spacer.height` tall in `bar.spacer.line`, with `bar.spacer.inset` either side.

Each side section sits in a `Zone` of `Bar.qml` that draws in the room from its bar edge, after `bar.padding`, to the centre section, less `bar.gap`; the centre keeps its own width. A zone whose widgets do not fit clips them and scrolls by whole widgets, from its buttons, the wheel or keyboard focus on a hidden widget. Each button is a bar item on `bar.scroll.backdrop`, beside a fade `bar.scroll.fade` wide that ends in `bar.scroll.clear`. At rest a zone shows the widgets nearest its bar edge. Each zone section declares the box it draws in, the part that shows whole widgets and `reveal`, so a drag over the zone drops into its section beside the widgets it shows and the zone scrolls to show the preview gap and the dropped widget.

`hidden` hides the bar on every screen; its surface is unmapped, so it reserves no space. The launcher's Hide top bar row and the shortcut `vgs.bar:toggle` flip it.

The clock ticks once a minute, or once a second when the format shows seconds.

The bar takes no keyboard focus. Keyboard access to a workspace uses the user's own Hyprland workspace binds.

The bar's service registers the shortcut `vgs.bar:toggle` and the IPC function `toggle` while the bar is the active one. The IPC call is the same toggle as the shortcut:

```text
vgshell ipc call vgs.bar invoke toggle ''
```
