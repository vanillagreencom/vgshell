# Settings

Manage your plugins, settings and shortcuts. Open Settings with `SUPER+M` or the gear in the bar.

![The launcher's page in the Settings window](../../../docs/images/plugins/vgs.settings-page.webp)

Screenshot made with `scripts/readme-shots.sh` in the nested sandbox, with the default theme at scale 2.

## Features

- Search for a plugin and open its page.
- Turn plugins on or off.
- Show a plugin in the bar while its other features stay on.
- Change a plugin's settings and shortcuts.
- Check a plugin's status and install its missing tools.
- Add, update or remove installed plugins.

## The window

Settings opens on the focused monitor. Click a plugin to open its page. Use the title menu to select another plugin. Escape returns to the list, then closes the window.

A plugin page has two pages. Settings holds the plugin's switches, setup screens, settings and shortcuts. Details shows what the plugin does, its current status and its tools. Turn on the plugin to change its settings and shortcuts. Under Setup, each button opens one of the plugin's setup screens. Under Keys, select a shortcut and press its new keys. The reset button restores the default shortcut. A plugin with a page in the system settings window ends with a button that opens that page. A plugin with a list of items, such as the pads of Scratchpads, has a section for it: Add appends an item, Remove deletes one, and each item's settings sit under its name. When one of your own Hyprland binds uses the same keys, Use my binding turns off the plugin's shortcut, so your bind keeps the keys.

On Details, Install all missing shows the missing tools before you install them. A status row's button opens a step you must complete. Connect opens a masked field for an account key. Save stores it in your keyring. Disconnect removes it. Show command reveals a step's command. A status row's button and its command show only while the step is needed.

Add plugin asks for the plugin's address. Update shows the changes before you apply them. Remove asks before it deletes the plugin. Each opens a setup window. Settings stays open behind it and shows the result when the step ends.

## Settings in the bar

Show in bar removes the gear while the shortcut still opens Settings. Turning off Settings removes the window, gear and shortcut. Its page keeps the command to turn it on behind Show command.

## Developer interface

| Path | How |
|---|---|
| IPC | `vgshell ipc call vgs.settings invoke toggle '<payload>'` or `... invoke open '<payload>'`, or the host's `vgshell ipc call shell summon window vgs.settings '<payload>'`. |

The payload is `{}` for the list, or `{"plugin":"<id>"}` for that plugin's page. An id no plugin has opens the list with a notice naming it. Any other key refuses the summon with `refused: open-failed=vgs.settings`. A script, a key or a launcher menu entry opens a page through `vgshell ipc call shell summon window vgs.settings '{"plugin":"<id>"}'`. Another plugin cannot open it through its `surfaces` capability, which opens only that plugin's own surfaces.
